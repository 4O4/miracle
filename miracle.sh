#!/usr/bin/env bash

# Miracle installer v0.2.1
# Copyright (c) 2017 Paweł Kierzkowski
# License: MIT
# Home: https://github.com/4O4/miracle

# Format strings
readonly INSTALLATION_STARTED_FORMAT="\n\e[4;92m%s\e[m\n\n"
readonly INSTALLATION_FINISHED_FORMAT="\n\e[4;92m%s\e[m\n\n"

# Ugly globals
processed_elements=0

# Trapped magic
main() {
	trap 'set +x; error ${LINENO}' ERR

	printf -- "--------------------------------------------------\n"
	printf -- " Miracle installer v0.2.1 by PK\n"
	printf -- "--------------------------------------------------\n"

	if [[ -z ${username} ]] || [[ -z ${password} ]]; then
		printf "Missing username or password!\n\n"
		return;
	fi;

	if [ ${#views[@]} -gt 0 ]; then
		install_with_sqlplus $'\n  Do you want to install SQL views?' views[@] ";"
	fi;

	if [ ${#packages[@]} -gt 0 ]; then
		install_with_sqlplus $'\n  Do you want to install PL/SQL packages?' packages[@] "/"
	fi;

	if [ ${#ebs_functions[@]} -gt 0 ]; then
		install_with_fndload $'\n  Do you want to import EBS functions?' "afsload.lct" ebs_functions[@]
	fi;

	if [ ${#ebs_concurrent_programs[@]} -gt 0 ]; then
		install_with_fndload $'\n  Do you want to import EBS concurrent programs?' "afcpprog.lct" ebs_concurrent_programs[@]
	fi;

	if [ ${#forms_libraries[@]} -gt 0 ]; then
		if confirm $'\n  Do you want to install Forms PL/SQL libraries?'; then
			for i in "${forms_libraries[@]}"
			do
				library_path=${i}
				library_full_filename=${i##*/}
				library_filename=${form_full_filename%.*}

				if [[ ! -z "${i}" ]] && confirm "    - ${i}"; then
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
		if confirm $'\n  Do you want to install Forms modules?'; then
			for i in "${forms_modules[@]}"
			do
				metadata=${i%;*}
				form_language=${metadata%;*}
				form_application=${metadata##*;}
				form_path=${i##*;}
				form_full_filename=${i##*/}
				form_filename=${form_full_filename%.*}
				the_top="${form_application}_TOP"

				if [[ ! -z "${i}" ]] && confirm "    - ${form_path} (language: ${form_language}, application: ${form_application})"; then
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

	if [ "${processed_elements}" -gt 0 ]; then
		print_stats
		print_log_reminder
	else
		printf "\nNothing to do here, bye\n\n"
	fi;

	# Consider opening pull request on Github if you add or fix something, thanks!
}

confirm() {
	local prompt_text="$1"

	while true; do
		printf "${prompt_text}"
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
	trap 'set +x; error ${LINENO}' ERR

	if [[ -z "$2" ]]; then return; fi;

	local prompt_text="$1"
	local config_array=("${!2}")
	local command_terminator="$3"

	if confirm "$1"; then
		config_array=("${!2}")

		for i in "${config_array[@]}"
		do
			if [[ ! -z "${i}" ]] && confirm "    - ${i}"; then
				final_terminator="${command_terminator}"

				# Avoid double command terminator
				last_character="$(cat ${i} | dos2unix | tr -d "[:space:]" | tail -c 1)"

				if [[ "${last_character}" = "${final_terminator}" ]]; then
					final_terminator=""
				fi;

				sqlplus -s ${username}/${password} <<-EOF
				printf "${INSTALLATION_STARTED_FORMAT}" "Installing ${i}..."
					SET SQLBLANKLINES ON
					SET DEFINE OFF
					WHENEVER SQLERROR EXIT FAILURE
					WHENEVER OSERROR EXIT FAILURE
					@${i}
					${final_terminator}
				EOF

				printf "${INSTALLATION_FINISHED_FORMAT}" "Finished installing ${i}"
				
				processed_elements=$((processed_elements + 1))
			fi;
		done
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
			if [[ ! -z "${i}" ]] && confirm "    - ${i}"; then
				printf "${INSTALLATION_STARTED_FORMAT}" "Installing ${i}..."
				result="$(FNDLOAD ${username}/${password} 0 Y UPLOAD ${FND_TOP}/patch/115/import/${fndload_script_name} ${i} UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1)"

				fndload_exit_code=$?

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
				
				if [[ ! ${fndload_exit_code} -eq 0 ]]; then
					error ${LINENO}
				fi;

				printf "${INSTALLATION_FINISHED_FORMAT}" "Finished installing ${i}"
				
				processed_elements=$((processed_elements + 1))
			fi;
		done
	fi;
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
