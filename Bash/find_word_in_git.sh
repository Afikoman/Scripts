#!/bin/bash

declare git_path_list_file='/opt/Afik/git_path_list.txt'
declare search_word='7.4'
declare script_path=$(pwd)
declare output_full_file_name='output_full.txt'
declare output_repo_list_file_name='output_repo_list.txt'

# Special echo functions.
function echo_log()
{
message=$1
/bin/echo -e "${PURPLE}$message${NOCOLOR}"
}
function echo_fail()
{
message=$1
/bin/echo -e "${RED}$message${NOCOLOR}"
}

function echo_success()
{
message=$1
/bin/echo -e "${GREEN}$message${NOCOLOR}"
}

function check_file_exists()
{
path=$1
if [ -e $path ]; then
	echo_fail "The '$path' already exists."
	exit 1
fi
}


# Main
output_full_file_full_path="$script_path/$output_full_file_name"
check_file_exists $output_full_file_full_path
output_repo_list_full_path="$script_path/$output_repo_list_file_name"
check_file_exists $output_repo_list_full_path
touch $output_full_file_full_path $output_full_file_full_path

rm -rf ./AfikArbiv_Git_Files
mkdir ./AfikArbiv_Git_Files
cd ./AfikArbiv_Git_Files

for git_path in $(cat $git_path_list_file)
do
        git clone $git_path
done

all_git_folders=$(ls -d */ | cut -f1 -d '/')
for git_folder in $all_git_folders
do
	cd $git_folder
	git grep -i -q $search_word
	if [ $? -ne 0 ]; then
		cd ..
		continue
	else
		echo "$git_folder" >> $output_repo_list_full_path
		echo "***********************************" >> $output_full_file_full_path
		echo "***    Repo name: $git_folder    ***" >> $output_full_file_full_path
		git grep -A 1 -B 1 --color -i $search_word >> $output_full_file_full_path
		cd ..
	fi
done
