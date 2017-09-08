#!/usr/bin/env bash

username="apps"
password=""

views=(
	# Example:
	# "PATH/TO/SCRIPT.sql"

)

packages=(
	# Example:
	# "PATH/TO/SCRIPT.(pkb|pks)"

)

ebs_functions=(
	# Example:
	# "PATH/TO/SCRIPT.ldt"

)

ebs_concurrent_programs=(
	# Example:
	# "PATH/TO/SCRIPT.ldt"

)

ebs_profiles=(
	# Example:
	# "PATH/TO/SCRIPT.ldt"

)

ebs_messages=(
	# Example:
	# "LANG_CODE;ORACLE_APPLICATION_SHORTNAME;PATH/TO/SCRIPT.ldt"

)

forms_libraries=(
	# Example:
	# "PATH/TO/LIBRARY.pll"

)

forms_modules=(
	# Example:
	# "LANG_CODE;ORACLE_APPLICATION_SHORTNAME;PATH/TO/MODULE.fmb"

)

custom=(
	# Example:
	# "Group name;Element name (can be empty if group name is unique);shell commands"

)

source "miracle.sh"