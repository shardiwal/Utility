#!/bin/bash

### USES ###
#  # Create a package from a git repository
#
#  # Go to git repository
# ./create_package.sh <from_gitcommit_id> <to_gitcommit_id> <path_where_you_want_package_to_store>
#
############

# MySQL Credentials
USER='db_user';
PASSWORD='db_password';
DATABASE='db_name';

#Today Timestamp
DATE=$(date +"%Y%m%d%H%M")

# Target directory
TARGET=$3
echo "Coping to $TARGET"

for i in $(git diff --name-only $1 $2)
    do
        # First create the target directory, if it doesn't exist.
        mkdir -p "$TARGET/$(dirname $i)"
        # Then copy over the file.
        cp "$i" "$TARGET/$i"
    done
echo "Done";

echo "Taking mysql backup";
mysqldump -u$USER -p$PASSWORD $DATABASE > "$TARGET/$DATABASE.sql";
echo "Database Dump Done";

echo "Compressing it";
tar -cvzf "$TARGET$DATE.tar.gz" "$TARGET";
echo "CREATED $TARGET$DATE.tar.gz";