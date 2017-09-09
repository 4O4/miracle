#!/usr/bin/env bash

# Miracle installer v0.4.1
# Copyright (c) 2017 Paweł Kierzkowski
# License: MIT
# Home: https://github.com/4O4/miracle

# Format strings
readonly INSTALLATION_STARTED_FORMAT="\n\e[4;92m%s\e[m\n\n"
readonly INSTALLATION_FINISHED_FORMAT="\n\e[4;92m%s\e[m\n\n"
readonly CONFIRM_GROUP_FORMAT="\n  %s"
readonly CONFIRM_ELEMENT_FORMAT="    - \e[96m%s\e[m"

# Ugly globals
processed_elements=0

# Trapped magic
main() {
	trap 'set +x; error ${LINENO}' ERR

	printf -- "--------------------------------------------------\n"
	printf -- " Miracle installer v0.4.1 by PK\n"
	printf -- "--------------------------------------------------\n"

	if [[ -z ${username} ]] || [[ -z ${password} ]]; then
		printf "Missing username or password!\n\n"
		return;
	fi;

	if [ ${#views[@]} -gt 0 ]; then
		install_with_sqlplus "${CONFIRM_GROUP_FORMAT} Do you want to install SQL views?" views[@] ";"
	fi;

	if [ ${#packages[@]} -gt 0 ]; then
		install_with_sqlplus "${CONFIRM_GROUP_FORMAT} Do you want to install PL/SQL packages?" packages[@] "/"
	fi;

	if [ ${#ebs_functions[@]} -gt 0 ]; then
		install_with_fndload "${CONFIRM_GROUP_FORMAT} Do you want to import EBS functions?" "afsload.lct" ebs_functions[@]
	fi;

	if [ ${#ebs_concurrent_programs[@]} -gt 0 ]; then
		install_with_fndload "${CONFIRM_GROUP_FORMAT} Do you want to import EBS concurrent programs?" "afcpprog.lct" ebs_concurrent_programs[@]
	fi;

	if [ ${#ebs_profiles[@]} -gt 0 ]; then
		install_with_fndload "${CONFIRM_GROUP_FORMAT} Do you want to import EBS profiles?" "afscprof.lct" ebs_profiles[@]
	fi;

	if [ ${#ebs_messages[@]} -gt 0 ]; then
		install_ebs_messages "${CONFIRM_GROUP_FORMAT} Do you want to import EBS messages?" ebs_messages[@]
	fi;

	if [ ${#forms_libraries[@]} -gt 0 ]; then
		if confirm "${CONFIRM_GROUP_FORMAT} Do you want to install Forms PL/SQL libraries?"; then
			for i in "${forms_libraries[@]}"
			do
				library_path=${i}
				library_full_filename=${i##*/}
				library_filename=${library_full_filename%.*}

				if [[ ! -z "${i}" ]] && confirm "${CONFIRM_ELEMENT_FORMAT}" "${i}"; then
					printf "${INSTALLATION_STARTED_FORMAT}" "Installing ${i}..."
					cp -f ${library_path} ${AU_TOP}/resource
					frmcmp_batch.sh module=${AU_TOP}/resource/${library_full_filename} userid=${username}/${password} output_file=${AU_TOP}/resource/${library_filename}.plx module_type=library compile_all=special
					printf "${INSTALLATION_FINISHED_FORMAT}" "Finished installing ${i}"
					
					processed_elements=$((processed_elements + 1))
				fi;
			done
		fi;
	fi;


	if [ ${#forms_modules[@]} -gt 0 ]; then
		if confirm "${CONFIRM_GROUP_FORMAT} Do you want to install Forms modules?"; then
			for i in "${forms_modules[@]}"
			do
				metadata=${i%;*}
				form_language=${metadata%;*}
				form_application=${metadata##*;}
				form_path=${i##*;}
				form_full_filename=${i##*/}
				form_filename=${form_full_filename%.*}
				the_top="${form_application}_TOP"

				if [[ ! -z "${form_path}" ]] && confirm "${CONFIRM_ELEMENT_FORMAT}" "${form_path} (language: ${form_language}, application: ${form_application})"; then
					printf "${INSTALLATION_STARTED_FORMAT}" "Installing ${form_path} (language: ${form_language}, application: ${form_application})..."
					cp -f ${form_path} ${AU_TOP}/forms/${form_language}
					env FORMS_PATH="${FORMS_PATH}:${AU_TOP}/forms/${form_language}" \
					frmcmp_batch.sh module=${AU_TOP}/forms/${form_language}/${form_full_filename} userid=${username}/${password} output_file=${!the_top}/forms/${form_language}/${form_filename}.fmx module_type=form compile_all=special
					printf "${INSTALLATION_FINISHED_FORMAT}" "Finished installing ${form_path} (language: ${form_language}, application: ${form_application})"
					
					processed_elements=$((processed_elements + 1))
				fi;
			done
		fi;
	fi;

	if [ ${#custom[@]} -gt 0 ]; then
		install_custom_resources custom[@]
	fi;

	if [ "${processed_elements}" -gt 0 ]; then
		print_stats
		print_log_reminder
	else
		printf "\nNothing to do here, bye\n\n"
	fi;

	# Consider opening pull request on Github if you add or fix something, thanks!
}

confirm() {
	while true; do
		printf "$@"
		read -p " [y/N] " yn
		case ${yn} in
			[Yy] ) return 0;;
			* ) return 1;;
		esac
	done
}

print_stats() {
	printf "\nProcessed ${processed_elements} elements\n"
}

print_log_reminder() {
	printf "\n\n\n!!! Log saved to 'install.log' file, PLEASE ATTACH IT TO THE JIRA TASK !!!\n\n"
}

install_with_sqlplus() {
#	trap 'set +x; error ${LINENO}' ERR

	if [[ -z "$2" ]]; then return; fi;

	local prompt_text="$1"
	local config_array=("${!2}")
	local command_terminator="$3"

	if confirm "$1"; then
		config_array=("${!2}")

		for i in "${config_array[@]}"
		do
			if [[ ! -z "${i}" ]] && confirm "${CONFIRM_ELEMENT_FORMAT}" "${i}"; then
				final_terminator="${command_terminator}"

				# Avoid double command terminator
				last_character="$(cat ${i} | remove_whitespace | tail -c 1)"

				if [[ "${last_character}" = "${final_terminator}" ]]; then
					final_terminator=""
				fi;

				show_errors_cmd="$(cat ${i} | remove_newline | grep -Pio 'create.*?(package|package body|view|procedure).*?[i|a]s' | perl -pe 's/create.*?(package body|package|view|procedure).*?((["]?[a-z]{1,20}["]?\.)?["]?[a-zA-Z0-9_]{1,30}["]?).*?[i|a]s/show errors \1 \2;/gi' | tr -d "\"")"
 
				printf "MIRACLE INFO: show_errors_cmd: ${show_errors_cmd}\n\n"

				printf "${INSTALLATION_STARTED_FORMAT}" "Installing ${i}..."
				result=$(sqlplus -s ${username}/${password} <<-EOF
					SET TERMOUT ON
					SET SQLBLANKLINES ON
					SET DEFINE OFF
					SET ECHO ON
					WHENEVER SQLERROR EXIT FAILURE
					WHENEVER OSERROR EXIT FAILURE
					@${i}
					${final_terminator}
					show errors
					${show_errors_cmd}
				EOF
)
				sqlplus_exit_code=$?

				printf "${result}"

				if [[ ! ${sqlplus_exit_code} -eq 0 ]] || [[ "${result}" == *"Errors for "* ]]; then
					error ${LINENO}
				fi

				printf "${INSTALLATION_FINISHED_FORMAT}" "Finished installing ${i}"
				
				processed_elements=$((processed_elements + 1))
			fi;
		done
	fi;
}

run_fnd_command_verbose() {
	if [[ -z "$1" ]]; then return; fi;

	local cmd="$@"

	result="$(${cmd} 2>&1)"

	cmd_exit_code=$?

	printf "${result}\n"
	
	log_file_name="$(echo ${result} | grep 'Log' | sed 's/Log filename : \(.*\.log\).*/\1/')"
	report_file_name="$(echo ${result} | grep 'Report' | sed 's/.*Report filename : \(.*\.out\).*/\1/')"

	printf "\n"

	if [[ -f "${log_file_name}" ]]; then
		cat "${log_file_name}"
	else
		printf "MIRACLE INFO: File '${log_file_name}' does not exist\n"
	fi;

	printf "\n"
	
	if [[ -f "${report_file_name}" ]]; then
		cat "${report_file_name}"
	else
		printf "MIRACLE INFO: File '${report_file_name}' does not exist\n"
	fi;
	
	if [[ ! ${cmd_exit_code} -eq 0 ]]; then
		error ${LINENO}
	fi;
}

install_with_fndload() {
	# No trap here because FNDLOAD log files should always be cat'ed.
	# Error must be raised manually.

	if [[ -z "$3" ]]; then return; fi;

	local prompt_text="$1"
	local fndload_script_name="$2"
	local config_array=("${!3}")

	if confirm "${prompt_text}"; then
		for i in "${config_array[@]}"
		do
			if [[ ! -z "${i}" ]] && confirm "${CONFIRM_ELEMENT_FORMAT}" "${i}"; then
				printf "${INSTALLATION_STARTED_FORMAT}" "Installing ${i}..."
				
				run_fnd_command_verbose \
				"FNDLOAD ${username}/${password} 0 Y UPLOAD ${FND_TOP}/patch/115/import/${fndload_script_name} ${i} UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE"

				printf "${INSTALLATION_FINISHED_FORMAT}" "Finished installing ${i}"
				
				processed_elements=$((processed_elements + 1))
			fi;
		done
	fi;
}

install_ebs_messages() {
	if [[ -z "$2" ]]; then return; fi;

	local prompt_text="$1"
	local config_array=("${!2}")

	if confirm "${prompt_text}"; then
		for i in "${config_array[@]}"
		do
			metadata=${i%;*}
			language=${metadata%;*}
			application=${metadata##*;}
			messages_file_path=${i##*;}

			if [[ ! -z "${messages_file_path}" ]] && confirm "${CONFIRM_ELEMENT_FORMAT}" "${messages_file_path} (language: ${language}, application: ${application})"; then
				printf "${INSTALLATION_STARTED_FORMAT}" "Installing ${messages_file_path} (language: ${language}, application: ${application})..."
				
				run_fnd_command_verbose \
				"FNDLOAD ${username}/${password} 0 Y UPLOAD ${FND_TOP}/patch/115/import/afmdmsg.lct ${messages_file_path} UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE"

				printf "\n"

				printf "${INSTALLATION_STARTED_FORMAT}" "Generating messages (DB to Runtime)..."

				run_fnd_command_verbose \
				"FNDMDGEN ${username}/${password} 0 Y ${language} ${application} DB_TO_RUNTIME"

				printf "${INSTALLATION_FINISHED_FORMAT}" "Finished installing ${messages_file_path} (language: ${language}, application: ${application})"
				
				processed_elements=$((processed_elements + 1))
			fi;
		done
	fi;
}

install_custom_resources() {
	if [[ -z "$1" ]]; then return; fi;

	local config_array=("${!1}")
	local last_group_name=""
	local last_group_confirmed=1

	for i in "${config_array[@]}"
	do
		group_name=${i%%;*}
		group_name=$(trim "${group_name}")
		rest=${i#*;}
		element_name=${rest%%;*}
		element_name=$(trim "${element_name}")
		commands=${rest#*;}

		if [[ ! -z "${commands}" ]] && [[ ! -z "${group_name}" ]]; then
			if [ "${last_group_name}" == "${group_name}" ]; then
				if [[ ${last_group_confirmed} -eq 0 ]]; then
					confirmed_group=0
				fi;
			else
				confirm "${CONFIRM_GROUP_FORMAT}" "Do you want to install ${group_name}?"
				confirmed_group=$?
			fi;

			last_group_name="${group_name}"
			last_group_confirmed=${confirmed_group}

			if [[ ${confirmed_group} -eq 0 ]]; then
				if [[ ${#config_array[@]} -eq 1 ]] && [[ -z "${element_name}" ]]; then
					confirmed_element=0
				else
					confirm "${CONFIRM_ELEMENT_FORMAT}" "${element_name}"
					confirmed_element=$?
				fi;

				if [[ ${confirmed_element} -eq 0 ]]; then
					printf "${INSTALLATION_STARTED_FORMAT}" "Installing ${group_name}${element_name:+ -> ${element_name}}..."

					printf "MIRACLE INFO: Commands to execute: ${commands}\n\n"
					
					result="$(${commands} 2>&1)"

					cmd_exit_code=$?

					printf "${result}\n"
					
					if [[ ! ${cmd_exit_code} -eq 0 ]]; then
						error ${LINENO}
					fi;

					printf "${INSTALLATION_FINISHED_FORMAT}" "Finished installing ${element_name:-${group_name}}"
					
					processed_elements=$((processed_elements + 1))
				fi;
			fi;
		fi;
	done
}

trim() {
	echo "$@" | xargs
}

remove_whitespace() {
	dos2unix | tr -d "[:space:]"
}

remove_newline() {
	dos2unix | tr "\n" " "
}

error() {
	local parent_lineno="$1"
	local message="$2"
	local code="${3:-1}"

	echo -n -e "\n\n$(basename ${BASH_SOURCE[0]}): \033[0;31m"
	if [[ -n "$message" ]] ; then
		echo "Error near line ${parent_lineno}: ${message}; exiting with status ${code}"
	else
		echo "Error near line ${parent_lineno}; exiting with status ${code}"
	fi
	echo -e "\033[0m"

	print_stats
	print_log_reminder

	exit "${code}"
}

# Log rotation
if [ -f "install.log" ]; then
	mv "install.log" "install_$(date +%Y-%m-%d_%H-%M-%S -r install.log).log"
fi

# Stdout + logging
exec &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' > "install.log"))
main
