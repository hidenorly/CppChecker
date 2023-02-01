#!/bin/bash

# Copyright 2023 hidenory
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if [ $# -eq 0 ]; then
	echo "This script is expected to create daily report"
	echo "Usage : targetProjectPath reportOutPath (CppCheckerOpts)"
	echo "e.g. ~/work/android-s ~/tmp/cppcheck \"-c https://android.googlesource.com/ -f system/\""
	exit
fi

# config
CPPCHECKER_TARGET_SRC=$1
BASE_PATH_REPORT_OUT=$2
CPPCHECKER_OPTS=$3

# should change to your environment
CPPCHECKER_PATH=~/work/CppChecker/CppChecker.rb
MD_DIFF_PATH=~/work/MarkdownTableDiff/md-diff.rb
DIR_UTIL_PATH=~/work/dir-util/dir-util.rb

# set non-config part
NEW_REPORT_DATE=$(date +%Y%m%d)
DIFF_REPORT_OUT_PATH=$BASE_PATH_REPORT_OUT/diff
NEW_DATE_REPORT_PATH=$BASE_PATH_REPORT_OUT/$NEW_REPORT_DATE

# ensure directory
mkdir $BASE_PATH_REPORT_OUT > /dev/null 2>&1
mkdir $DIFF_REPORT_OUT_PATH > /dev/null 2>&1

# get old report date
rm -rf $NEW_DATE_REPORT_PATH
OLD_REPORT_DATE=`ruby $DIR_UTIL_PATH -n 1 -t $BASE_PATH_REPORT_OUT -o reverse -f "[0-9]+"`
OLD_DATE_REPORT_PATH=$BASE_PATH_REPORT_OUT/$OLD_REPORT_DATE
mkdir $NEW_DATE_REPORT_PATH > /dev/null 2>&1

# Cppchecker
mkdir $NEW_DATE_REPORT_PATH > /dev/null 2>&1
ruby $CPPCHECKER_PATH -p $NEW_DATE_REPORT_PATH $CPPCHECKER_TARGET_SRC $CPPCHECKER_OPTS

# Diff cppchecker's report
DIFF_REPORT_FILENAME=$DIFF_REPORT_OUT_PATH/diff-$OLD_REPORT_DATE-$NEW_REPORT_DATE.md
TMP_DIFF_REPORT_FILENAME=$DIFF_REPORT_OUT_PATH/_diff-$OLD_REPORT_DATE-$NEW_REPORT_DATE.md

ruby $MD_DIFF_PATH $OLD_DATE_REPORT_PATH $NEW_DATE_REPORT_PATH -f -s "summary.md,*" -i "line" -n -c $TMP_DIFF_REPORT_FILENAME

echo "# Diff between $OLD_REPORT_DATE and $NEW_REPORT_DATE" > $DIFF_REPORT_FILENAME
if [ -e $TMP_DIFF_REPORT_FILENAME ]; then
	cat $TMP_DIFF_REPORT_FILENAME >> $DIFF_REPORT_FILENAME
	rm $TMP_DIFF_REPORT_FILENAME
else
	echo "No difference" >> $DIFF_REPORT_FILENAME
fi
echo "" >> $DIFF_REPORT_FILENAME
echo "# [Summary](summary.md)" >> $DIFF_REPORT_FILENAME
echo "" >> $DIFF_REPORT_FILENAME
cat $NEW_DATE_REPORT_PATH/summary.md  >> $DIFF_REPORT_FILENAME

echo $DIFF_REPORT_FILENAME
