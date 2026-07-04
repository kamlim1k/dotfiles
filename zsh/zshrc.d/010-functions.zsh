function assume-role() {
  local ROLE_ARN="$1"
  local REGION="${2:-us-east-1}"               # default region
  local SOURCE_PROFILE="${3:-live-admin}"      # your SSO profile
  local SESSION_NAME="${4:-cli-session}"

  if [[ -z "$ROLE_ARN" ]]; then
    echo "Usage: assume-role <role-arn> [region] [source-profile] [session-name]"
    return 1
  fi

  echo "🔐 Assuming role:"
  echo "  Role ARN       : $ROLE_ARN"
  echo "  Region         : $REGION"
  echo "  Source Profile : $SOURCE_PROFILE"
  echo "  Session Name   : $SESSION_NAME"

  local CREDS=$(aws sts assume-role \
        --role-arn "$ROLE_ARN" \
            --role-session-name "$SESSION_NAME" \
                --profile "$SOURCE_PROFILE" \
                    --region "$REGION" \
                        --output json)

  if [[ -z "$CREDS" || "$CREDS" == "null" ]]; then
    echo "❌ Failed to assume role. Check role ARN and SSO login."
    return 1
  fi

  export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | jq -r '.Credentials.AccessKeyId')
  export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r '.Credentials.SecretAccessKey')
  export AWS_SESSION_TOKEN=$(echo "$CREDS" | jq -r '.Credentials.SessionToken')
  export AWS_REGION="$REGION"
  export AWS_DEFAULT_REGION="$REGION"

  echo "✅ Role assumed and credentials exported. Current identity:"
  aws sts get-caller-identity
}

delete-secrets-by-prefix() {
  # Parse --dry-run flag from anywhere in args, collect the rest as positional
  local dry_run=false
  local -a args=()
  for arg in "$@"; do
    if [[ "$arg" == "--dry-run" || "$arg" == "-n" ]]; then
      dry_run=true
    else
      args+=("$arg")
    fi
  done

  local prefix="${args[1]}"
  local profile="${args[2]}"
  local recovery_days="${args[3]:-7}"

  # Validate required args
  if [[ -z "$prefix" || -z "$profile" ]]; then
    echo "Usage: delete-secrets-by-prefix <prefix> <profile> [recovery_days] [--dry-run|-n]"
    echo "  prefix         Secret name prefix to match (required)"
    echo "  profile        AWS CLI profile to use (required)"
    echo "  recovery_days  Days before permanent deletion, 7-30 (default: 7)"
    echo "  --dry-run, -n  Show what would be deleted without deleting"
    return 1
  fi

  # Validate recovery_days is in valid range
  if ! [[ "$recovery_days" =~ ^[0-9]+$ ]] || (( recovery_days < 7 || recovery_days > 30 )); then
    echo "Error: recovery_days must be an integer between 7 and 30 (got '$recovery_days')"
    return 1
  fi

  # Verify profile exists and works
  local account_id
  account_id=$(aws sts get-caller-identity --profile "$profile" --query 'Account' --output text 2>/dev/null)
  if [[ -z "$account_id" ]]; then
    echo "Error: AWS profile '$profile' is not configured or credentials are invalid."
    return 1
  fi

  # Fetch matching secrets
  local secrets
  secrets=(${(f)"$(aws secretsmanager list-secrets \
    --profile "$profile" \
    --query "SecretList[?starts_with(Name, '$prefix')].Name" \
    --output text 2>/dev/null | tr '\t' '\n')"})

  if (( ${#secrets[@]} == 0 )); then
    echo "No secrets match prefix '$prefix' in account $account_id."
    return 0
  fi

  # Show plan
  echo "AWS Account:     $account_id"
  echo "Profile:         $profile"
  echo "Prefix:          $prefix"
  echo "Recovery window: $recovery_days days"
  if $dry_run; then
    echo "Mode:            DRY RUN (no changes will be made)"
  fi
  echo ""
  echo "Matched ${#secrets[@]} secret(s):"
  printf '  %s\n' "${secrets[@]}"
  echo ""

  # Dry run: stop here
  if $dry_run; then
    echo "Dry run complete. Re-run without --dry-run to actually schedule deletion."
    return 0
  fi

  # Confirm
  echo -n "Proceed? [y/N] "
  read confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    return 1
  fi

  # Execute deletions
  echo ""
  local success=0 failed=0
  for s in "${secrets[@]}"; do
    echo "Scheduling deletion: $s"
    local deletion_date
    deletion_date=$(aws secretsmanager delete-secret \
      --profile "$profile" \
      --secret-id "$s" \
      --recovery-window-in-days "$recovery_days" \
      --query 'DeletionDate' \
      --output text 2>/dev/null)
    if [[ -n "$deletion_date" && "$deletion_date" != "None" ]]; then
      echo "  ✓ scheduled for $deletion_date"
      ((success++))
    else
      echo "  ✗ failed"
      ((failed++))
    fi
  done

  echo ""
  echo "Summary: $success succeeded, $failed failed"
  if (( success > 0 )); then
    echo ""
    echo "To restore a secret within the recovery window:"
    echo "  aws secretsmanager restore-secret --profile $profile --secret-id <name>"
  fi
}
