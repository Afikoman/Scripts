#!/bin/bash

##############################################################
# Author: Afik Arbiv
# Description: Script to install Elasticsearch Cluter.
# Date (Last modify): 02/11/19
##############################################################

# Pre-requests:
#	* Run this script only with root privileges.
#	* Change the variables of the nodes information.

# This script runs locally on a new CentOS server.
# This script do the following:
#	* Install Java 1.8.
#	* Install Vim.
#	* Create .repo file for elasticsearch packages
#	* Install Elastic Search 7.4
#	* Add all elasticsearch nodes to /etc/hosts.
#	* Edit the elasticsearch.yml file.
#	* Starting elasticsearch and making it starts on boot.
#	* Open ports 9200 9300 from all other nodes.

# You may (and should) change the nodes information variables.

# Script exit codes:
# 1  - Script run as non root.
# 2  - Failed to install Java.
# 3  - Failed to import GPG-KEY for elasticsearch repository.
# 4  - Failed to install Elastic.
# 5  - Failed to edit /etc/hosts.
# 6  - Failed to start Elastic.
# 7  - Failed to enable Elastic to start automatically on boot.
# 8  - Failed to create a firewall rule.
# 9  - Failed to reload firewall changes.
# 10 - Failed to create the elasticsearch repo file.
# 11 - Failed to insert data to a file.
# 12 - Failed to create a file.
# 13 - Failed to create a partition.
# 14 - Physical volume (PV) creation failed.
# 15 - Volume Group (VG) already exists.
# 16 - Volume group (VG) creation failed.
# 17 - Logical volume (LV) already exists.
# 18 - Logical volume (LV) creation failed.
# 19 - Failed to create a file system.
# 20 - Data directory path already exists.
# 21 - Failed to create a directory.
# 22 - Failed to change owner (of a file / directory).
# 23 - Failed to edit the /etc/fstab.
# 24 - Failed to mount.
# 25 - Failed to install httpd.
# 26 - Failed to start httpd.
# 27 - Failed to enable httpd to start automatically on boot.

##############################################################

#####	You should change this variables section - Start	######

# Variables for the nodes information.
declare cluster_name='es-cluster'
declare node_name_convention='es-c77-m-'
declare node_ip_convention='10.0.0.'
declare node_last_number_ip_begin=4	# The last number in the IP of the first node in the range (assuming all IP are in sequence).
declare num_of_nodes=3

# Variables default defenition for the configuration.
declare is_master_eligible=true
declare is_data_node=true

# Variable for the data disk.
declare data_disk_path='/dev/sdc'
declare data_dir_path='/mnt/data'
declare vg_data_name='VolGroup-Data'
declare lv_data_name='LogVol-Data'

# Variable for the load balancer probe configuration.
declare probe_file_name='healthcheck.aspx'

######	You should change this variables section - End	   #######

# Configure the colors for the logs.
declare -r NOCOLOR='\033[0m'
declare -r RED='\033[0;31m'
declare -r PURPLE='\033[0;35m'
declare -r GREEN='\033[0;32m'

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

function echo_fail_wipe_message()
{
echo_fail "----------------------------------------------------"
echo_fail "The script is not wiping the data disk. you can do it manually by using the command."
echo_fail "dd if=/dev/zero of=<disk_path> bs=1 count=512"
echo_fail "Use it carefully!!! This command can not be reversed."
echo_fail "----------------------------------------------------"
}

# Cleaning function.
function clean_temp_files()
{
rm -f /tmp/AfikArbivNodesNameList.txt /tmp/AfikArbivNodesIPList.txt /tmp/AfikArbivNodeNamesWithComma.txt /tmp/AfikArbivNodesIPListWithoutMe.txt
}


# Confirmation that the user running the script is root.
if [ $(id -u) -ne 0 ]; then
	echo_fail "You must be root in order to run this script."
	exit 1
fi

# Installing Java, and vim rpms (vim for convenient).
yum install java-1.8.0-openjdk-devel java-1.8.0-openjdk -y
if [ $? -ne 0 ]; then
	echo_fail "Java installation failed."
	exit 2
fi

yum install vim -y
if [ $? -ne 0 ]; then
	echo_log "Vim installation failed. Continue anyway."
fi

# Importing GPG-KEY for elasticsearch repository.
rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
if [ $? -ne 0 ]; then
	echo_fail "Failed to import GPG-KEY for elasticsearch repository."
	echo_fail "Please check that the url 'https://artifacts.elastic.co/GPG-KEY-elasticsearch' is reachable."
	exit 3
fi

## Configuring elasticsearch repository.
# Checking if the repository file exists.
if [ -f /etc/yum.repos.d/elasticsearch7.repo ]; then
	echo_log "The repository file '/etc/yum.repos.d/elasticsearch7.repo' already exists."
	echo_log "Trying to continue without editing it."
	echo_log "If the installation of the elasticsearch fails, please delete/edit this repository file manually and run this script again."
else
	touch /etc/yum.repos.d/elasticsearch7.repo
	if [ $? -ne 0 ]; then
		echo_fail "Failed to create the file '/etc/yum.repos.d/elasticsearch7.repo'."
		
		# Clean.
		clean_temp_files
		exit 12
	fi

		cat << EOF > /etc/yum.repos.d/elasticsearch7.repo
[elasticsearch-7.x]
name=Elasticsearch repository for 7.x packages
baseurl=https://artifacts.elastic.co/packages/7.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
EOF

	if [ $? -ne 0 ]; then
		echo_fail "Failed to create the elasticsearch repo file."
		
		# Delete the empty elasticsearch repository file we created.
		rm -f/etc/yum.repos.d/elasticsearch7.repo 
		# Clean.
		clean_temp_files
		exit 10
	fi
fi

# Installing elasticsearch.
yum install elasticsearch -y
if [ $? -ne 0 ]; then
	echo_fail "Failed to install elastic."
        exit 4
fi

# Creating a file contains a list of the nodes names.
rm -f /tmp/AfikArbivNodesNameList.txt
touch /tmp/AfikArbivNodesNameList.txt
if [ $? -ne 0 ]; then
	echo_fail "Failed to create the file '/tmp/AfikArbivNodesNameList.txt'."

	# Clean.
	clean_temp_files
	exit 12
fi

for i in `seq 1 $num_of_nodes`;
do
	echo ${node_name_convention}$i >> /tmp/AfikArbivNodesNameList.txt
	if [ $? -ne 0 ]; then
		echo_fail "Failed to insert data to the '/tmp/AfikArbivNodesNameList.txt' file."

		# Clean.
		clean_temp_files
		exit 11
	fi
done

# Creating a file contains a list of the nodes IPs.
rm -f /tmp/AfikArbivNodesIPList.txt
touch /tmp/AfikArbivNodesIPList.txt
if [ $? -ne 0 ]; then
	echo_fail "Failed to create the file '/tmp/AfikArbivNodesIPList.txt'."

	# Clean.
	clean_temp_files
	exit 12
fi

node_last_number_ip_end=$(($node_last_number_ip_begin + $num_of_nodes - 1))
for i in `seq $node_last_number_ip_begin $node_last_number_ip_end`;
do
	echo ${node_ip_convention}$i >> /tmp/AfikArbivNodesIPList.txt
	if [ $? -ne 0 ]; then
		echo_fail "Failed to insert data to the '/tmp/AfikArbivNodesNameList.txt' file."

		# Clean.
		clean_temp_files
		exit 11
	fi
done

# Inserting the Nodes to the /etc/hosts.
paste /tmp/AfikArbivNodesIPList.txt /tmp/AfikArbivNodesNameList.txt >> /etc/hosts
if [ $? -ne 0 ]; then
	echo_fail "Failed to edit the /etc/hosts file."
        exit 5
fi

## Creating the data mount directory.
# Create a partition on the data disk.
/bin/echo -e "n\np\n\n\n\nt\n8e\nw" | /sbin/fdisk $data_disk_path
if [ $? -ne 0 ]; then
	echo_fail "Failed to create a partition on the disk: '$data_disk_path'."
	# Clean.
	clean
	exit 13
fi
/sbin/partx -av /dev/sdc &>/dev/null

# Create the physical volume.
pvcreate ${data_disk_path}1
if [ $? -ne 0 ]; then
	echo_fail "PV creation failed."
	# Clean.
	clean
	exit 14
fi

# Check if the volume group already exists.
all_vg_names=$(vgs --noheading | /bin/awk {'print $1'})
if echo $all_vg_names | grep -q $vg_data_name; then
		echo_fail "The volume group named $vg_data_name already exists."
		echo_fail_wipe_message
		
		# Clean.
		clean
		exit 15
fi
# Create the volume group.
vgcreate $vg_data_name ${data_disk_path}1
if [ $? -ne 0 ]; then
	echo_fail "VG creation failed"
	echo_fail_wipe_message
	
	# Clean.
	clean
	exit 16	
fi

# Check if the logical volume already exists.
all_lv_names=$(lvs --noheading | /bin/awk {'print $1'})
if echo $all_lv_name | grep -q $lv_data_name; then
	echo_fail "The logical volume named $lv_data_name already exists."
	echo_fail_wipe_message
	
	# Clean.
	clean
	exit 17
fi
lvcreate -l 100%free -n $lv_data_name $vg_data_name
if [ $? -ne 0 ]; then
	echo_fail "LV creation failed"
	echo_fail_wipe_message
	
	# Clean.
	clean
	exit 18	
fi

# Create a file system on the LV.
mkfs.xfs /dev/VolGroup-Data/LogVol-Data
if [ $? -ne 0 ]; then
	echo_fail "The creation of a xfs file system on the LV failed."
	echo_fail_wipe_message
	
	# Clean.
	clean
	exit 19	
fi

# Create the mount directory and give elasticsearch user owner.
# Check if the data directory exists.
if [ -e $data_dir_path ]; then
	# Check if its directory.
	echo_fail "The '$data_dir_path' already exists."
	echo_fail_wipe_message
	
	# Clean.
	clean
	exit 20
fi

mkdir $data_dir_path
if [ $? -ne 0 ]; then
	echo_fail "Failed to create the directory '$data_dir_path'."
	echo_fail_wipe_message
	
	# Clean.
	clean
	exit 21
fi

## Adding the data mount to the /etc/fstab
# Backing up the /etc/fstab file.
cp /etc/fstab /opt/AfikArbiv_fstab_backup

echo -e "/dev/$vg_data_name/$lv_data_name\t$data_dir_path\txfs\tdefaults\t0 0" >> /etc/fstab
if [ $? -ne 0 ]; then
	echo_fail "Failed to add the data mount to the /etc/fstab."
	echo_fail_wipe_message
	
	# Restore the /etc/fstab file.
	mv -f /opt/AfikArbiv_fstab_backup /etc/fstab
		
	# Clean.
	clean
	exit 23
fi

# Removing the backup /etc/fstab file.
rm -f /opt/AfikArbiv_fstab_backup

# Mount the data directory.
mount $data_dir_path
if [ $? -ne 0 ]; then
	echo_fail "Failed to mount '$data_dir_path' data mount."
	echo_fail_wipe_message
		
	# Clean.
	clean
	exit 24
fi

chown elasticsearch:elasticsearch $data_dir_path
if [ $? -ne 0 ]; then
	echo_fail "Failed to change the owner of the $data_dir_path directory to elasticsearch:elasticseach."
	echo_fail "Please make sure that the user and group named 'elasticsearch' exists."
	echo_fail_wipe_message
	
	# Clean.
	clean
	exit 22
fi

## Editing the elasticsearch.yml configuration.
# Replacing the lines with the willing content.
sed -i "/node.name: node-1/c\node.name: $HOSTNAME" /etc/elasticsearch/elasticsearch.yml
sed -i "/cluster.name: my-application/c\cluster.name: $cluster_name" /etc/elasticsearch/elasticsearch.yml
sed -i "/network.host: 192.168.0.1/c\network.host: [\"$HOSTNAME\", \"localhost\"]" /etc/elasticsearch/elasticsearch.yml
# Replace the path.data with the data directory we created.
sed -i "/path.data:/c\path.data: $data_dir_path" /etc/elasticsearch/elasticsearch.yml

# Adding the 'node.master' and 'node.data' params to the yaml file.
if [ "$is_master_eligible" = true ]; then
	sed -i '/node.name:*/a node.master: true' /etc/elasticsearch/elasticsearch.yml
else
	sed -i '/node.name:*/a node.master: false' /etc/elasticsearch/elasticsearch.yml
	echo_log "Please notice that this node is NOT master-eligible. You MUST config at least one other node as master-eligible."
fi

if [ "$is_data_node" = true ]; then
	sed -i '/node.name:*/a node.data: true' /etc/elasticsearch/elasticsearch.yml
else
	sed -i '/node.name:*/a node.data: false' /etc/elasticsearch/elasticsearch.yml
	echo_log "Please notice that this node is NOT a data node."
fi

## Editing the nodes names for inserting them to the yaml file
rm -f /tmp/AfikArbivNodeNamesWithComma.txt
# Adding double quotes at the start and the end of each name.
# Replacing the new line with a comma and a space.
cat /tmp/AfikArbivNodesNameList.txt | sed 's/^/\"/' | sed 's/$/\"/' | sed -z 's/\n/, /g' | rev | cut -c 3- | rev >> /tmp/AfikArbivNodeNamesWithComma.txt
if [ $? -ne 0 ]; then
	echo_fail "Failed to create the file '/tmp/AfikArbivNodeNamesWithComma.txt'."

	# Clean.
	clean_temp_files
	exit 12
fi

# Adding square brackets.
sed -i 's/^/[/' /tmp/AfikArbivNodeNamesWithComma.txt
sed -i 's/$/]/' /tmp/AfikArbivNodeNamesWithComma.txt
nodes_names_array=$(cat /tmp/AfikArbivNodeNamesWithComma.txt)

# Actual edit of the elasticsearch.yml file
sed -i "/cluster.initial_master_nodes/c\\cluster.initial_master_nodes: $nodes_names_array" /etc/elasticsearch/elasticsearch.yml
sed -i "/cluster.initial_master_nodes:*/a discovery.zen.ping.unicast.hosts: $nodes_names_array" /etc/elasticsearch/elasticsearch.yml

# Reload systemd manager configuration.
systemctl daemon-reload
if [ $? -ne 0 ]; then
	echo_log "Failed to reload systemd manager configuration. Trying to continue."
fi

# Starting Elasticsearch and make it start automatically on boot.
systemctl start elasticsearch
if [ $? -ne 0 ]; then
	echo_fail "Failed to start elasticsearch. Please check why and continue manually."
	echo_fail "Please also clean the temporary files manually when your done. The temp files are:"
	echo_fail "/tmp/AfikArbivNodesNameList.txt"
	echo_fail "/tmp/AfikArbivNodesIPList.txt"
	echo_fail "/tmp/AfikArbivNodeNamesWithComma.txt"
	echo_fail "/tmp/AfikArbivNodesIPListWithoutMe.txt"
	exit 6
fi

systemctl enable elasticsearch
if [ $? -ne 0 ]; then
	echo_fail "Failed to enable elastic start on boot. Please check why and continue manually."
	echo_fail "Please also clean the temporary files manually when your done. The temp files are:"
	echo_fail "/tmp/AfikArbivNodesNameList.txt"
	echo_fail "/tmp/AfikArbivNodesIPList.txt"
	echo_fail "/tmp/AfikArbivNodeNamesWithComma.txt"
	echo_fail "/tmp/AfikArbivNodesIPListWithoutMe.txt"
	exit 7
fi

## Open ports 9200 and 9300 on the firewall from all other nodes.
rm -f /tmp/AfikArbivNodesIPListWithoutMe.txt
# Generating file containing all of the other nodes IPs.
cat /etc/hosts | grep $node_name_convention | grep -v ${HOSTNAME} | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" > /tmp/AfikArbivNodesIPListWithoutMe.txt
if [ $? -ne 0 ]; then
	echo_fail "Failed to create the file '/tmp/AfikArbivNodesIPListWithoutMe.txt'."

	# Clean.
	clean_temp_files
	exit 12
fi

## Add firewall rules.
# Check if the local firewall is active.
if systemctl status firewalld.service | grep -q 'dead' ; then
	echo_log "The firewalld.service is down. No need to open ports."
else
	for node_ip in $(cat /tmp/AfikArbivNodesIPListWithoutMe.txt);
	do
		firewall-cmd --permanent --zone=public --add-rich-rule="
	rule family="ipv4"
	source address="$node_ip/32"
	port protocol="tcp" port="9200" accept"
	
		if [ $? -ne 0 ]; then
			echo_fail "-----------------------------------------------------------"
			echo_fail "Failed to create firewall rich rule for $node_ip port 9200."
			echo_fail "Please create this rule manually after this script is done."
			echo_fail "-----------------------------------------------------------"
	
			# Clean
			clean_temp_files
			exit 8
		fi
	
		firewall-cmd --permanent --zone=public --add-rich-rule="
	rule family="ipv4"
	source address="$node_ip/32"
	port protocol="tcp" port="9300" accept"
	
		if [ $? -ne 0 ]; then
			echo_fail "-----------------------------------------------------------"
			echo_fail "Failed to create firewall rich rule for $node_ip port 9300."
			echo_fail "Please create this rule manually after this script is done."
			echo_fail "-----------------------------------------------------------"
	
			# Clean
			clean_temp_files
			exit 8
		fi
		
	done
	
	# Reload firewall configuration.
	firewall-cmd --reload
	if [ $? -ne 0 ]; then
		echo_fail "Failed to reload firewall changes."
		echo_fail "Please check for the reason and update the firewall configuration manually."
	
		# Clean
		clean_temp_files
		exit 9
	fi
fi

# Clean
clean_temp_files

echo_success "The ElasticSearch installation script finished successfully."

## Create web path for the health probe of the load balancer.
# Install httpd rpm.
yum install httpd -y
if [ $? -ne 0 ]; then
	echo_fail "Failed to install httpd rpm."
	exit 25
fi

# Create the web file for the load balancer probe check.
if [ -e /var/www/html/$probe_file_name  ]; then
        echo_log "healthcheck.aspx already exists. Continue."
else
        echo "I am server $HOSTNAME" > /var/www/html/$probe_file_name
		if [ $? -ne 0 ]; then
			echo_fail "Failed to create the healthcheck file."
			exit 12
		fi
fi

# Starting Elasticsearch and make it start automatically on boot.
systemctl start httpd
if [ $? -ne 0 ]; then
	echo_fail "Failed to start httpd." 
	exit 26
fi

systemctl enable httpd
if [ $? -ne 0 ]; then
	echo_fail "Failed to enable httpd start on boot."
	exit 27
	
fi

## Add firewall rule.
# Check if the local firewall is active.
if systemctl status firewalld.service | grep -q 'dead' ; then
	echo_log "The firewalld.service is down. No need to open ports."
else
	firewall-cmd --permanent --add-port=80/tcp
	if [ $? -ne 0 ]; then
		echo_fail "-----------------------------------------------------------"
		echo_fail "Failed to create firewall rule for port 80."
		echo_fail "Please create this rule manually after this script is done."
		echo_fail "-----------------------------------------------------------"
		exit 9
	fi
	
	# Reload firewall configuration.
	firewall-cmd --reload
	if [ $? -ne 0 ]; then
		echo_fail "Failed to reload firewall changes."
		echo_fail "Please check for the reason and update the firewall configuration manually."
		
		# Clean
		clean_temp_files
		exit 10
	fi
	
fi

echo_success "Succesfully created the $probe_file_name for the load balancer. Enjoy :)"
