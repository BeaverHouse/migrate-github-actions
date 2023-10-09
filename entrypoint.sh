#!/bin/sh -l

set -e  # if a command fails it stops the execution
set -u  # script fails if trying to access to an undefined variable

echo "[+] Action start"
APP_TYPE="${1}"
DESTINATION_GITHUB_USERNAME="BeaverHouse"
DESTINATION_REPOSITORY_NAME="untitled@4f6edd6e-1218-4e21-87d9-41d686e7746e"	 # falsy value
GITHUB_SERVER="github.com"
USER_EMAIL="haulrest@naver.com"
USER_NAME="LHU"
DESTINATION_REPOSITORY_USERNAME="BeaverHouse"
TARGET_BRANCH="main"
COMMIT_MESSAGE="Migrate data from other repository"

if [ $APP_TYPE = "aecheck" ]
then
	DESTINATION_REPOSITORY_NAME="aecheck-v3"
elif [ $APP_TYPE = "bluearchive-torment" ]
then
	DESTINATION_REPOSITORY_NAME="bluearchive-torment-search"
else
	echo "::error::APP_TYPE not vaild"
	exit 1
fi


# Verify that there (potentially) some access to the destination repository
# and set up git (with GIT_CMD variable) and GIT_CMD_REPOSITORY
if [ -n "${SSH_DEPLOY_KEY:=}" ]
then
	echo "[+] Using SSH_DEPLOY_KEY"

	# Inspired by https://github.com/leigholiver/commit-with-deploy-key/blob/main/entrypoint.sh , thanks!
	mkdir --parents "$HOME/.ssh"
	DEPLOY_KEY_FILE="$HOME/.ssh/deploy_key"
	echo "${SSH_DEPLOY_KEY}" > "$DEPLOY_KEY_FILE"
	chmod 600 "$DEPLOY_KEY_FILE"

	SSH_KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"
	ssh-keyscan -H "$GITHUB_SERVER" > "$SSH_KNOWN_HOSTS_FILE"

	export GIT_SSH_COMMAND="ssh -i "$DEPLOY_KEY_FILE" -o UserKnownHostsFile=$SSH_KNOWN_HOSTS_FILE"

	GIT_CMD_REPOSITORY="git@$GITHUB_SERVER:$DESTINATION_REPOSITORY_USERNAME/$DESTINATION_REPOSITORY_NAME.git"
else
	echo "::error::SSH_DEPLOY_KEY are empty. Please fill one"
	exit 1
fi


CLONE_DIR=$(mktemp -d)

echo "[+] Git version"
git --version

echo "[+] Enable git lfs"
git lfs install

echo "[+] Cloning destination git repository $DESTINATION_REPOSITORY_NAME"

# Setup git
git config --global user.email "$USER_EMAIL"
git config --global user.name "$USER_NAME"

# workaround for https://github.com/cpina/github-action-push-to-another-repository/issues/103
git config --global http.version HTTP/1.1

{
	git clone --single-branch --depth 1 --branch "$TARGET_BRANCH" "$GIT_CMD_REPOSITORY" "$CLONE_DIR"
} || {
	echo "::error::Could not clone the destination repository. Command:"
	echo "::error::git clone --single-branch --branch $TARGET_BRANCH $GIT_CMD_REPOSITORY $CLONE_DIR"
	echo "::error::(Note that if they exist USER_NAME and API_TOKEN is redacted by GitHub)"
	echo "::error::Please verify that the target repository exist AND that it contains the destination branch name, and is accesible by the API_TOKEN_GITHUB OR SSH_DEPLOY_KEY"
	exit 1

}
ls -la "$CLONE_DIR"

TEMP_DIR=$(mktemp -d)
# This mv has been the easier way to be able to remove files that were there
# but not anymore. Otherwise we had to remove the files from "$CLONE_DIR",
# including "." and with the exception of ".git/"
mv "$CLONE_DIR/.git" "$TEMP_DIR/.git"

# $TARGET_DIRECTORY is '' by default
TARGET_ROOT_DIRECTORY="$CLONE_DIR"

if [ $APP_TYPE = "aecheck" ]
then
	echo "[+] Deleting data"
	rm -rf "$TARGET_ROOT_DIRECTORY/public/image/data"
	rm -rf "$TARGET_ROOT_DIRECTORY/src/data"
	rm -rf "$TARGET_ROOT_DIRECTORY/src/i18n"
	rm -rf "$TARGET_ROOT_DIRECTORY/src/constant/updates.ts"

	echo "[+] Creating (now empty) directory"
	mkdir -p "$TARGET_ROOT_DIRECTORY/public/image/data"
	mkdir -p "$TARGET_ROOT_DIRECTORY/src/data"
	mkdir -p "$TARGET_ROOT_DIRECTORY/src/i18n"

	echo "[+] Copying contents of source repository folder"
	cp -ra "v3_result/image/." "$TARGET_ROOT_DIRECTORY/public/image/data"
	cp -ra "v3_result/data/." "$TARGET_ROOT_DIRECTORY/src/data"
	cp -ra "v3_result/i18n/." "$TARGET_ROOT_DIRECTORY/src/i18n"
	cp -ra "v3_result/updates.ts" "$TARGET_ROOT_DIRECTORY/src/constant/updates.ts"
else
	echo "[+] Deleting data"
	rm -rf "$TARGET_ROOT_DIRECTORY/src/data"
	rm -rf "$TARGET_ROOT_DIRECTORY/src/constant.js"

	echo "[+] Creating (now empty) directory"
	mkdir -p "$TARGET_ROOT_DIRECTORY/src/data"

	echo "[+] Copying contents of source repository folder"
	cp -ra "result_detail/." "$TARGET_ROOT_DIRECTORY/src/data"
	cp -ra "other/constant.js" "$TARGET_ROOT_DIRECTORY/src/constant.js"
fi

mv "$TEMP_DIR/.git" "$CLONE_DIR/.git"


cd "$CLONE_DIR"

echo "[+] Files that will be pushed"
ls -la

ORIGIN_COMMIT="https://$GITHUB_SERVER/$GITHUB_REPOSITORY/commit/$GITHUB_SHA"
COMMIT_MESSAGE="${COMMIT_MESSAGE/ORIGIN_COMMIT/$ORIGIN_COMMIT}"
COMMIT_MESSAGE="${COMMIT_MESSAGE/\$GITHUB_REF/$GITHUB_REF}"

echo "[+] Set directory is safe ($CLONE_DIR)"
# Related to https://github.com/cpina/github-action-push-to-another-repository/issues/64
git config --global --add safe.directory "$CLONE_DIR"

echo "[+] Adding git commit"
git add .

echo "[+] git status:"
git status

echo "[+] git diff-index:"
# git diff-index : to avoid doing the git commit failing if there are no changes to be commit
git diff-index --quiet HEAD || git commit --message "$COMMIT_MESSAGE"

echo "[+] Pushing git commit"
# --set-upstream: sets de branch when pushing to a branch that does not exist
git push "$GIT_CMD_REPOSITORY" --set-upstream "$TARGET_BRANCH"
