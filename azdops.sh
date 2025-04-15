#!/bin/bash

set -e

: ${NOPROMPT=false}

unset CODESPACES
unset GITHUB_TOKEN

msg() {
	echo ">>> $*" >&2
}

run() {
	msg "Running: $@"
	"$@"
}

confirm() {
	if $NOPROMPT; then
		return
	fi
	read -p ">>> Continue? [y/N] " -n 1 -r >&2
	echo >&2
	case "$REPLY" in
		y) return ;;
	esac
	exit 1
}

load_config() {
	msg "Loading azdops config from $1"
	test -d azdops/node_modules || ( cd azdops && npm i >/dev/null 2>&1)
	npx -y -p ./azdops -c "load-yaml $1"
}

enable_remote_env() {
	msg 'Updating ~/.azd/config.yaml to enable the azd remote env'
	confirm
	run azd config set state.remote.backend AzureBlobStorage
	run azd config set state.remote.config.accountName $1
}

disable_remote_env() {
	msg 'Updating ~/.azd/config.yaml to disable the azd remote env'
	confirm
	run azd config unset state
}

set_keyvault_policy() {
	UPN=$(run az account show --query user.name -o tsv)
	case "$UPN" in
	*@*) run az keyvault set-policy -n "$1" --secret-permissions all purge --certificate-permissions all purge --upn $UPN -o none ;;
	*) run az keyvault set-policy -n "$1" --secret-permissions all purge --certificate-permissions all purge --spn $UPN -o none ;;
	esac
}

cmd_config() {
	load_config .github/azdops
}

cmd_auth() {
	eval $(load_config .github/azdops)

	AZURE_TEMP_DIR=$(mktemp -d)
	export AZURE_CONFIG_DIR=$AZURE_TEMP_DIR
	msg "Logging in with Azure CLI as user (saved in $AZURE_CONFIG_DIR)"
	run az config set --only-show-errors core.login_experience_v2=off
	run az login -t=$AZURE_TENANT_ID >/dev/null
	run az account set -s $AZURE_SUBSCRIPTION_ID
	run az account show
	set_keyvault_policy $AZD_REMOTE_ENV_KEY_VAULT_NAME
	PASSWORD=$(run az keyvault secret show --vault-name $AZD_REMOTE_ENV_KEY_VAULT_NAME --name "AZURE-CLIENT-SECRET-${AZURE_CLIENT_ID}" --query value -o tsv || true)

	msg "Deleting the temporary directory"
	run rm -rf $AZURE_TEMP_DIR

	if test -z "$PASSWORD"; then
		msg "E: Failed to get the password from the key vault: run ./azdops.sh auth-az-secret"
		exit 1
	fi

	msg "Logging in with Azure CLI as service principal"
	unset AZURE_CONFIG_DIR
	echo -n "$PASSWORD" | run az login --service-principal -u $AZURE_CLIENT_ID -t $AZURE_TENANT_ID -p @/dev/stdin -o none
	run az account set -s $AZURE_SUBSCRIPTION_ID
	run az account show
	run azd config set auth.useAzCliAuth true
}

cmd_secret() {
	eval $(load_config .github/azdops)
	if test -z "$AZD_REMOTE_ENV_KEY_VAULT_NAME"; then
		msg "E: AZD_REMOTE_ENV_KEY_VAULT_NAME is not set"
		exit 1
	fi
	if test "$1" != "reset"; then
		PASSWORD=$(run az keyvault secret show --vault-name $AZD_REMOTE_ENV_KEY_VAULT_NAME --name "AZURE-CLIENT-SECRET-${AZURE_CLIENT_ID}" --query value -o tsv || true)
		if test -n "$PASSWORD"; then
			msg "I: Secret is already set in the key vault"
			exit 0
		fi
	fi
	if test -n "$AZURE_CLIENT_SECRET"; then
		msg "I: Set the secret in AZURE_CLIENT_SECRET"
		PASSWORD=$AZURE_CLIENT_SECRET
	else
		msg "I: Creating a new secret"
		DISPLAY_NAME="$GITHUB_REPOSITORY $(date -u +%Y-%m-%dT%H:%M:%SZ)"
		PASSWORD=$(run az ad app credential reset --only-show-errors --id $AZURE_CLIENT_ID --append --display-name "$DISPLAY_NAME" --end-date 2299-12-31 --query password --output tsv)
	fi
	echo -n "$PASSWORD" | run az keyvault secret set --vault-name $AZD_REMOTE_ENV_KEY_VAULT_NAME --name "AZURE-CLIENT-SECRET-${AZURE_CLIENT_ID}" --file /dev/stdin -o none
}

cmd_env() {
	eval $(load_config .github/azdops)
	if test -n "$AZD_REMOTE_ENV_STORAGE_ACCOUNT_NAME"; then
		enable_remote_env $AZD_REMOTE_ENV_STORAGE_ACCOUNT_NAME
	else
		disable_remote_env
	fi
	run azd config set auth.useAzCliAuth true
	run azd env list
}

cmd_clear() {
	disable_remote_env
	run azd env list
}

cmd_help() {
	msg "Usage: $0 <command> [options...] [args...]"
	msg "Options:"
	msg "  --help,-h      - Show this help"
	msg "  --no-prompt    - Do not ask for confirmation"
	msg "Commands:"
	msg "  auth           - Run \"az login\""
	msg "  secret [reset] - Save Azure client secret in the key vault"
	msg "  env            - Set up AZD remote env"
	msg "  clear          - Clear the azd remote env"
	exit $1
}

OPTIONS=$(getopt -o h -l help,no-prompt -- "$@")
if test $? -ne 0; then
	cmd_help 1
fi

eval set -- "$OPTIONS"

while true; do
	case "$1" in
		-h|--help)
			cmd_help 0
			;;
		--no-prompt)
			NOPROMPT=true
			shift
			;;
		--)
			shift
			break
			;;
		*)
			msg "E: Invalid option: $1"
			cmd_help 1
			;;
	esac
done

if test $# -eq 0; then
	msg "E: Missing command"
	cmd_help 1
fi

case "$1" in
	config)
		shift
		cmd_config "$@"
		;;
	auth)
		shift
		cmd_auth "$@"
		;;
	secret)
		shift
		cmd_secret "$@"
		;;
	env)
		shift
		cmd_env "$@"
		;;
	clear)
		shift
		cmd_clear "$@"
		;;
	*)
		msg "E: Invalid command: $1"
		cmd_help 1
		;;
esac