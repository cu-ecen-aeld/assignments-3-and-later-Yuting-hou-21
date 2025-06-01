#!/bin/sh
# Tester script for AESD Assignment 4
# Author: Siddhant Jajoo

set -e

# Verify executables in PATH
command -v writer >/dev/null 2>&1 || { echo "writer not found in PATH"; exit 1; }
command -v finder.sh >/dev/null 2>&1 || { echo "finder.sh not found in PATH"; exit 1; }

# Config files
CONF_DIR=/etc/finder-app/conf
USERNAME_FILE=${CONF_DIR}/username.txt
ASSIGNMENT_FILE=${CONF_DIR}/assignment.txt

[ -f "${USERNAME_FILE}" ] || { echo "username.txt not found in ${CONF_DIR}"; exit 1; }
[ -f "${ASSIGNMENT_FILE}" ] || { echo "assignment.txt not found in ${CONF_DIR}"; exit 1; }

# Read username
username=$(cat "${USERNAME_FILE}")

# Test writer
TEST_DIR=/tmp/aeld-data
TEST_FILE=${TEST_DIR}/${username}.txt
TEST_STRING="AESD Assignment 4 Test"
mkdir -p "${TEST_DIR}"
writer "${TEST_FILE}" "${TEST_STRING}"
[ -f "${TEST_FILE}" ] || { echo "writer failed to create ${TEST_FILE}"; exit 1; }
grep -q "${TEST_STRING}" "${TEST_FILE}" || { echo "writer content mismatch in ${TEST_FILE}"; exit 1; }

# Test finder.sh
OUTPUT=/tmp/assignment4-result.txt
finder.sh "${TEST_DIR}" "${TEST_STRING}" > "${OUTPUT}"
[ -f "${OUTPUT}" ] || { echo "finder.sh failed to create ${OUTPUT}"; exit 1; }

# Verify finder.sh output
MATCHSTR="The number of files are 1 and the number of matching lines are 1"
grep -q "${MATCHSTR}" "${OUTPUT}" || { echo "finder.sh output mismatch, expected ${MATCHSTR}"; exit 1; }

# Check syslog for writer messages
if ! grep -q "writer" /var/log/messages; then
    echo "No writer messages found in /var/log/messages"
    exit 1
fi

echo "All tests passed!"
exit 0
