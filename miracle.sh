#!/usr/bin/env bash

# Miracle installer v0.1.0 - prototype
# Copyright (c) 2017 Paweł Kierzkowski
# License: MIT
# Home: https://github.com/4O4/miracle

# Ugly globals
processed_elements=0

# Trapped magic
main() {
	trap 'set +x; error ${LINENO}' ERR

	printf -- "--------------------------------------------------\n"
	printf -- " Miracle installer v0.1.1 by PK\n"
	printf -- "--------------------------------------------------\n"

	if [[ -z ${username} ]] || [[ -z ${password} ]]; then
		printf "Missing username or password!\n\n"
		return;
	fi;

	if [ ${#views[@]} -gt 0 ]; then
		install_with_sqlplus $'\n  Do you want to install SQL views?' views[@]
	fi;

	if [ ${#packages[@]} -gt 0 ]; then
		install_with_sqlplus $'\n  Do you want to install PL/SQL packages?' packages[@]
	fi;

	if [ ${#ebs_functions[@]} -gt 0 ]; then
		if confirm $'\n  Do you want to import EBS functions?'; then
			for i in "${ebs_functions[@]}"
			do
				if [[ ! -z "${i}" ]] && confirm "    - ${i}"; then
					printf "\nInstalling ${i}...\n\n"
					FNDLOAD ${username}/${password} 0 Y UPLOAD ${FND_TOP}/patch/115/import/afsload.lct ${i} UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE WARNINGS=YES
					printf "\nFinished installing ${i}\n\n"
					
					processed_elements=$((processed_elements + 1))
				fi;
			done
		fi;
	fi;

	if [ ${#forms_libraries[@]} -gt 0 ]; then
		if confirm $'\n  Do you want to install Forms PL/SQL libraries?'; then
			for i in "${forms_libraries[@]}"
			do
				library_path=${i}
				library_full_filename=${i##*/}
				library_filename=${form_full_filename%.*}

				if [[ ! -z "${i}" ]] && confirm "    - ${i}"; then
					printf "\nInstalling ${i}...\n\n"
					cp -f ${library_path} ${AU_TOP}/resource
					frmcmp_batch.sh module=${AU_TOP}/resource/${library_full_filename} userid=${username}/${password} output_file=${AU_TOP}/resource/${library_filename}.plx module_type=library compile_all=special
					printf "\nFinished installing ${i}\n\n"
					
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
					printf "\nInstalling ${form_path} (language: ${form_language}, application: ${form_application})...\n\n"
					cp -f ${form_path} ${AU_TOP}/forms/${form_language}
					env FORMS_PATH="${FORMS_PATH}:${AU_TOP}/forms/${form_language}" \
					frmcmp_batch.sh module=${AU_TOP}/forms/${form_language}/${form_full_filename} userid=${username}/${password} output_file=${!the_top}/forms/${form_language}/${form_filename}.fmx module_type=form compile_all=special
					printf "\nFinished installing ${form_path} (language: ${form_language}, application: ${form_application})\n\n"
					
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
    while true; do
        read -p "$1 [y/N] " yn
        case $yn in
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

	if confirm "$1"; then
		config_array=${!2}

		for i in "${config_array[@]}"
		do
			if [[ ! -z "${i}" ]] && confirm "    - ${i}"; then
				printf "\nInstalling ${i}...\n\n"
				sqlplus -s ${username}/${password} <<-EOF
					WHENEVER SQLERROR EXIT FAILURE
					WHENEVER OSERROR EXIT FAILURE
					@${i}
				EOF
				printf "\nFinished installing ${i}\n\n"
				
				processed_elements=$((processed_elements + 1))
			fi;
		done
	fi;
}

error() {
	local parent_lineno="$1"
	local message="$2"
	local code="${3:-1}"

	echo -n -e "\n\n$(basename $0): \033[0;31m"
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
exec &> >(tee -a "install.log")
main