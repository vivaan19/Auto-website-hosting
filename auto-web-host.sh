#!/bin/bash
: ' 

Script to make an ubuntu instance (Free tier) < check if one-instance is running if yes then modify in the existing instace > ; ssh into it ; install apache2, zip, unzip ; download template from tooplate ; let user-choose which type of website to host ; then retart the server ; and then give the pulic ip from which it can be accessed 

--- Measures to take :: 
1. Check if the security group exists on tcp port 80 and any ipv4 can access it and if that security is not created then create it and assign it to current instace. 

---- Algo :

1. Check if there is any instace in running state 

cmd : aws ec2 describe-instances 
	
	check length of reservation 
	
	0, 1, or >1 

	if 0 then create new instance 

	if 1 then check state --- running, stopped, terminated 

		if running then ok -- further commands can be executed 

		if stopped then bring it to running state 

		if terminated then -- create new instance 
	
	if >1 then check for the ami with debian based distribution and check the latest instance status -- if running then further commands can be executed 
		
		-- if stopped then extract its id and bring vm into start state

	Todo: 

	1. Give .pem files 400 permission means only root user can be able to read and write 
		
'

################# INTERNET CONNECTION CHECKING #####################

if ! ping www.google.com &>/dev/null; then

	echo ERROR1: INTERNET NOT CONNECTED
	exit 1

else

	PROFILE="/home/$(whoami)/.profile"
	source "$PROFILE"

fi

################### GLOBAL VARIABLES #################################

KP_NAME='kp-'$RANDOM

KP_FILE=$KP_NAME'.pem'

KP_DIR="aws_kp_dir"

#######################################################################


################# FUNCTION TO CREATE NEW INSTANCE ###########################

newIns() {

	echo "SECURITY GROUP CREATION WITH TCP 80 IPV4/V6 EVERYWHERE and KEY PAIR FILE my-key-pair.pem ....."

	############ CREATING AND CHECKING FOR EXISTING KEY-PAIR #####################

	####### CONVENTION - KEY-PAIR FILE NAME = KEY-PAIR-NAME.PEM


	# CHECK IF PEM FILE DIRECTORY EXISTS

	if [ -d "/var/$KP_DIR" ]; then

		echo "INFO ################### KEY-PAIR DIR EXIST"

		######### CHECK IF KP EXISTS IN SYSTEM DON'T NEED TO MAKE EXTRA KP  ##########
		# CONVERTING JSON ARRAY OBJECT TO BASH OBJECT

		EXISTING_KP=$(aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' | jq -r '.[]')

		EXISTING_KP_NAME="none"

		for element1 in $EXISTING_KP; do

			for element2 in $(sudo ls /var/$KP_DIR); do

				if [[ "$element1" == "$(echo "$element2" | cut -d "." -f1)" ]]; then

					EXISTING_KP_NAME=$element1

					KP_NAME=$EXISTING_KP_NAME

				fi
			done
		done

		# IF KEY-PAIR DOES'T EXIST THEN MAKE ANOTHER KEY-PAIR

		if [[ "$EXISTING_KP_NAME" == "none" ]]; then

			aws ec2 create-key-pair --key-name "$KP_NAME" --key-type rsa --key-format pem  --query 'KeyMaterial' --output text | sudo tee /var/$KP_DIR/$KP_FILE > /dev/null

		fi

	else
		echo "INFO ################### KEY-PAIR DIR DOES NOT EXIST"

		############## MAKE DIRECTORY AND KEY-PAIR #############

		sudo mkdir /var/$KP_DIR

		aws ec2 create-key-pair --key-name $KP_NAME --key-type rsa --key-format pem --query 'KeyMaterial' --output text | sudo tee /var/$KP_DIR/$KP_FILE > /dev/null
	fi

	echo ">>>>>>>>>>>>>>>> KEY-PAIR DETAILS" 

	echo "KEY-PAIR NAME - $KP_NAME ; KEY-PAIR LOCATION - /var/$KP_DIR/$KP_NAME.pem"

	sudo chmod 400 /var/$KP_DIR/"$KP_NAME".pem

	
	#####################################################
	############ CREATING SECURITY GROUP ################
	#####################################################

	SEC_GRP_NAME='sec_grp-'$RANDOM

	# Determine length of security group array

	SEC_GRP_LEN=$(aws ec2 describe-security-groups | jq '.SecurityGroups | length')

	if [ "$SEC_GRP_LEN" -eq 1 ]; then

		echo "INFO ################### SEC-GRP DOES NOT EXIST"

		# MAKE SECURITY GROUP

		SEC_GRP_ID=$(aws ec2 create-security-group --group-name $SEC_GRP_NAME --description "custom script security group" | jq '.GroupId')

		# NOW PROVIDE INGRESS RULES AS IT IS CREATED IN THE DEFAULT VPC NO NEED TO CREATE SSH PORT 22 RULE
		# PROVIDE TCP PORT 80 IPV4/V6 EVERYWHERE

		SEC_GRP_FORMAT=$(echo "$SEC_GRP_ID" | cut -d '"' -f2)

		# SSH
		aws ec2 authorize-security-group-ingress --group-id "$SEC_GRP_FORMAT" --protocol tcp --port 22 --cidr 0.0.0.0/0

		# IPV6
		aws ec2 authorize-security-group-ingress --group-id "$SEC_GRP_FORMAT" --ip-permissions '[{"IpProtocol": "tcp", "FromPort": 80, "ToPort": 80, "Ipv6Ranges": [{"CidrIpv6": "::/0"}]}]'

		# IPV4
		aws ec2 authorize-security-group-ingress --group-id "$SEC_GRP_FORMAT" --protocol tcp --port 80 --cidr 0.0.0.0/0

	else

		# REDIRECT DEC-SEC-GRP RESPOSE TO TEMP JSON FILE THEN PROCESS THAT FILE THROUGH JQ
		# CHECK IF ALREADY A SEC-GRP EXISTS WHICH HAS SAME INGRESS RULES

		echo "INFO ################### SEC-GRP EXISTS "

		TMP_FILE="/tmp/sec-grp.json"

		touch $TMP_FILE
		
		# CONVERTING INTO JSON AND STORING IN TMP_FILE 
		aws ec2 describe-security-groups | jq '.[]' > $TMP_FILE

		CHK_EXIST=false

		# MAIN LOOP
		for ((i = 0; i < $(jq '. | length' "$TMP_FILE"); i++)); do

			for ((j = 0; j < $(jq ".[$i].IpPermissions | length" "$TMP_FILE"); j++)); do
				
				FROM_PORT=$(jq ".[$i].IpPermissions[$j].FromPort" "$TMP_FILE")
				
				IP_PROTO=$(jq ".[$i].IpPermissions[$j].IpProtocol" "$TMP_FILE")

				IP_V4=$(jq ".[$i].IpPermissions[$j].IpRanges[0].CidrIp" "$TMP_FILE")
				
				IP_V6=$(jq ".[$i].IpPermissions[$j].Ipv6Ranges[0].CidrIpv6" "$TMP_FILE")

				if [[ "$FROM_PORT" == 80 && "$IP_PROTO" == '"tcp"' && "$IP_V4" == '"0.0.0.0/0"' && "$IP_V6" == '"::/0"' ]]; then

					SEC_GRP_ID=$(jq ".[$i].GroupId" $TMP_FILE)
					
					SEC_GRP_FORMAT=$(echo "$SEC_GRP_ID" | cut -d '"' -f2)
					
					CHK_EXIST=true
					
					break 2

				fi

			done

		done
	
		if [ "$CHK_EXIST" == "false" ]; then

			SEC_GRP_ID=$(aws ec2 create-security-group --group-name $SEC_GRP_NAME --description "custom script security group" | jq '.GroupId')

			SEC_GRP_FORMAT=$(echo "$SEC_GRP_ID" | cut -d '"' -f2)

			# SSH
			aws ec2 authorize-security-group-ingress --group-id "$SEC_GRP_FORMAT" --protocol tcp --port 22 --cidr 0.0.0.0/0

			# IPV6
			aws ec2 authorize-security-group-ingress --group-id "$SEC_GRP_FORMAT" --ip-permissions '[{"IpProtocol": "tcp", "FromPort": 80, "ToPort": 80, "Ipv6Ranges": [{"CidrIpv6": "::/0"}]}]'

			# IPV4
			aws ec2 authorize-security-group-ingress --group-id "$SEC_GRP_FORMAT" --protocol tcp --port 80 --cidr 0.0.0.0/0
		fi


	fi
	
	echo ">>>>>>>>>>>>>>>>>>> SECURITY GROUP ID - $SEC_GRP_FORMAT"

	echo "################# INFO CREATING Ubuntu Server 22.04 LTS"

	############ CREATE NEW INSTANCE AFTER ALL VALIDATION ############### 
	############ AMI - Ubuntu Server 22.04 LTS (HVM), SSD Volume Type x86 
	######################################################################

	INS_ID=$(aws ec2 run-instances \
    --image-id ami-0c7217cdde317cfec \
    --count 1 \
    --instance-type t2.micro \
    --key-name "$KP_NAME" \
    --security-group-ids "$SEC_GRP_FORMAT" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=web01-server}]' 'ResourceType=volume,Tags=[{Key=Name,Value=normal-ebs-vol}]' \
	| jq '.Instances[0].InstanceId')

	
	FOR_INS_ID=$(echo "$INS_ID" | cut -d '"' -f2)

	if [[ $? -eq 0 ]]; then 

		echo "################# INFO SERVER CREATED SUCCESSFULLY"
		echo "################# SERVER ID :: $INS_ID"

	else 

		echo "################# ERROR2 SERVER NOT ABLE TO CREATE"
		exit 2 
	fi

}

processInstallation() {

	FOR_INS_ID=$(echo "$1" | cut -d '"' -f2)

	echo "Formatted INS ID ---- $FOR_INS_ID"

	USER="ubuntu" 
	
	HOST=$(aws ec2 describe-instances --instance-ids "$FOR_INS_ID" | jq '.Reservations[].Instances[].PublicDnsName' | cut -d '"' -f2)
	
	echo "Host ---- $HOST"

	KEY="/var/$KP_DIR/$2.pem"
	
	echo "Key ---- $KEY"

	LINK_FILE="link_file.txt"

	BASH_FILE="commands.sh"


	############# ASK USER WHICH WEBSITE TO HOST #############

while true; do

    cat << EOF

    ENTER WHICH WEBSITE TO HOST :::

    PRESS 1 TO CAFE WEBSITE

    PRESS 2 TO MINI FINANCE

    PRESS 3 TO WEDDING LITE

    PRESS 4 TO MOSO INTERIOR

    PRESS 5 TO JOB SEARCH

EOF

    read -p "Enter your choice (1-5): " choice

    case $choice in
        1)
            echo "You selected CAFE WEBSITE."
            # Add your code for hosting CAFE WEBSITE here

			echo "https://www.tooplate.com/zip-templates/2137_barista_cafe.zip" > $LINK_FILE

            break
            ;;
        2)
            echo "You selected MINI FINANCE."
            # Add your code for hosting MINI FINANCE here

			echo "https://www.tooplate.com/zip-templates/2135_mini_finance.zip" > $LINK_FILE
            break
            ;;
        3)
            echo "You selected WEDDING LITE."
            # Add your code for hosting WEDDING LITE here

			echo "https://www.tooplate.com/zip-templates/2131_wedding_lite.zip" > $LINK_FILE
            break
            ;;
        4)
            echo "You selected MOSO INTERIOR."
            # Add your code for hosting MOSO INTERIOR here

			echo "https://www.tooplate.com/zip-templates/2133_moso_interior.zip" > $LINK_FILE

            break
            ;;
        5)
            echo "You selected JOB SEARCH."
            # Add your code for hosting JOB SEARCH here

			echo "https://www.tooplate.com/zip-templates/2134_gotto_job.zip" > $LINK_FILE

            break
            ;;
        *)
            echo "Invalid choice. Please enter a number between 1 and 5."
            ;;
    esac
done

cat << EOF > $BASH_FILE

#!/bin/bash

sudo apt update -y ; sudo apt upgrade -y

sudo apt install apache2 zip unzip -y

sudo systemctl start apache2 

sudo systemctl enable apache2

curl -O $(cat $LINK_FILE)

unzip $(cat $LINK_FILE | cut -d "/" -f5)

sudo rm -rf /var/www/html/*

sudo rsync -av --remove-source-files $(cat $LINK_FILE | cut -d "/" -f5 | cut -d "." -f1)/* /var/www/html/

sudo systemctl restart apache2 

rm -rf $(cat $LINK_FILE | cut -d "/" -f5)

rm -rf $(cat $LINK_FILE | cut -d "/" -f5 | cut -d "." -f1)

rm -rf $LINK_FILE

EOF


	scp_count=0

	while true; do

		sudo scp -o BatchMode=yes -o StrictHostKeyChecking=no -i "$KEY" $LINK_FILE $BASH_FILE $USER@"$HOST":~/ 2> /dev/null 
		
		if [[ $? -eq 0 ]]; then 

			echo "FILE TRANSFERRED SUCCESSFULLY"

			break
		fi

		if [[ $scp_count -eq 10 ]]; then 

			echo "ERROR3: LINK FILE CANNOT BE TRANSFERRED"

			break
		fi
		
		((scp_count++))

	done

	
	

	########### HERE WE WILL GET INSTANCE ID ############ 
	# 1. SSH INTO THE MACHINE THROUGH PEM KEY
	# 2. AND EXECUTE COMMANDS 

	
while true; do

sudo ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i "$KEY" $USER@"$HOST" << EOF > /dev/null 2>&1

sudo chmod u+x $BASH_FILE
./$BASH_FILE

EOF

	if [ $? -eq 0 ]; then
		echo "SITE HOSTED SUCCESSFULLY"
		break
	fi

	done

	PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$FOR_INS_ID" | jq '.Reservations[].Instances[].PublicIpAddress')

	echo "ACCESS YOUR WEBSITE USING THIS IP ========= $PUBLIC_IP"


}


############## CHECK HOW MANY INTANCES ARE PRESENT #######################
# IF -- RESERVATION COUNT IS 0 THEN CREATE NEW INSTANCE WITH ABOVE DETAILS AND DO THE FURTHER PROCESS 
# IF -- RESERVATION COUNT IS >= 1 THEN CHECK KEY-PAIR NAME AND IP_PERMISSIONS 
#	IF BOTH ARE SATISFIED THEN CHECK THE STATUS OF VM IF IT IS STOPPED THEN TURN ON AND DO THE FURTHER PROCESS 
#   ELSE THEN CREATE A NEW VM AND DO THE FURTHER PROCESS 
############## NOW CREATE INSTANCE WITH THE ABOVE DETAILS ################ 

# CHECK NUMBER OF INSTANCES 

INS_NUM=$(aws ec2 describe-instances --filters "Name=instance-state-name,Values=running,stopped" --query "Reservations[*].Instances[*].{Instance:InstanceId,State:State.Name}" | jq '. | length')

if [[ $INS_NUM -eq 0 ]]; then 

	# THIS CONDITION IS FOR NEW INSTANCE CREATION FROM SCRATCH 
	
	newIns

	# CONTINUE FURTHER ONLY IF THE INTANCE STATE IS IN RUNNING STATE 
	while true; do

		RES_LEN=$(aws ec2 describe-instances --instance-ids "$FOR_INS_ID" --filters "Name=instance-state-name,Values=running" | jq '.Reservations | length')

		if [ "$RES_LEN" -gt 0 ]; then
			
			processInstallation "$INS_ID" "$KP_NAME"
			break

		fi

	done


else

	TMP_FILE="/tmp/instance_list.json"

	aws ec2 describe-instances | jq '.' > $TMP_FILE

	INS_LEN=$(jq '.Reservations | length' $TMP_FILE)

	echo "$INS_LEN"	


	for (( i = 0; i < "$INS_LEN"; i++ )); do

		if [[ $(jq ".Reservations[$i].Instances[].State.Name" $TMP_FILE) == '"running"' || $(jq ".Reservations[$i].Instances[].State.Name" $TMP_FILE) == '"stopped"' ]]; then

			
			SEC_ID=$(jq ".Reservations[$i].Instances[].SecurityGroups[].GroupId" $TMP_FILE | cut -d '"' -f2)

			INS_KP=$(jq ".Reservations[$i].Instances[].KeyName" $TMP_FILE | cut -d '"' -f2)

			IP_V4=$(aws ec2 describe-security-groups --group-ids "$SEC_ID" | jq -r '.SecurityGroups[].IpPermissions[] | select(.IpProtocol=="tcp" and .FromPort==80)' | jq '.IpRanges[].CidrIp')

			IP_V6=$(aws ec2 describe-security-groups --group-ids "$SEC_ID" | jq -r '.SecurityGroups[].IpPermissions[] | select(.IpProtocol=="tcp" and .FromPort==80)' | jq '.Ipv6Ranges[].CidrIpv6')

			if [[ $IP_V4 == '"0.0.0.0/0"' && $IP_V6 == '"::/0"' ]] && [ -f "/var/$KP_DIR/$INS_KP.pem" ]; then

				if [[ $(jq ".Reservations[$i].Instances[].State.Name" $TMP_FILE) == '"running"' ]]; then

					INS_ID=$(jq ".Reservations[$i].Instances[].InstanceId" $TMP_FILE)

					processInstallation $INS_ID $INS_KP

				fi

			fi	

		fi

	done
	

fi