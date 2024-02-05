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

	echo "WARNING ################### INTERNET NOT CONNECTED"
	exit 1

else

	echo "INFO ################### SUCCESS INTERNET IS CONNECTED"

	echo "INFO ################### CHECKING REQUIRED SOFTWARE"

	which jq &> /dev/null

	if [ $? -ne 0 ]; then
		sudo apt install jq -y
	fi

	which htmlq &> /dev/null 
	if [ $? -ne 0 ]; then

		sudo curl -L --output htmlq.tar.gz $HTMLQ_LINK

		sudo tar xf htmlq.tar.gz -C /usr/local/bin

		rm -rf htmlq.tar.gz

	fi



	# EXPORT YOUR DEFAULT REGION, ACCESS KEY AND SECRET ACCESS KEY IN .profile file 
	
	: '

		IN THIS FORMAT :: 

		export AWS_DEFAULT_REGION=us-east-1
		export AWS_ACCESS_KEY_ID=AKIAUJ6NBCEXAMPLE
		export AWS_SECRET_ACCESS_KEY=D/tYoLYyvHZqEXAMPLE

	
	'

	PROFILE="$HOME/.profile"
	
	source "$PROFILE"

	# AFTER BEING SOURCED SCRIPT WILL BR USING THE CONFIGURATIONS AS MENTIONED 
fi

################### SCRIPT CONSTANTS #################################

# NEW KEY-PAIR NAME WILL BE IN THE FORMAT OF kp-$RANDOM 
# RANDOM WILL HAVE VALUES RANGING FROM 0 to 32767  
KP_NAME='kp-'$RANDOM

KP_FILE=$KP_NAME'.pem'

KP_DIR="aws_kp_dir"

SEC_GRP_NAME='sec_grp-'$RANDOM

TMP_FILE="/tmp/sec-grp.json"

USER="ubuntu" 

REM_STATUS_FILE="/opt/build_file.txt"

HTMLQ_LINK="https://github.com/mgdm/htmlq/releases/latest/download/htmlq-x86_64-linux.tar.gz"

#######################################################################


################# FUNCTION TO CREATE NEW INSTANCE ###########################

: '

	FUNCTION STEPS : 

	1. CHECK ATLEAST ONE KEY-PAIR FROM AWS IS PRESENT IN THE SYSTEM  

	2. 

'

newIns() {

	echo "INFO ################### NEW INSTANCE PROCESS STARTING ... "

	############ CREATING AND CHECKING FOR EXISTING KEY-PAIR #####################

	####### CONVENTION - KEY-PAIR FILE NAME = KEY-PAIR-NAME.PEM


	# CHECK IF PEM FILE DIRECTORY EXISTS

	if [ -d "/var/$KP_DIR" ]; then
		
		######### CHECK IF KP EXISTS IN SYSTEM ##########

		echo "INFO ################### KEY-PAIR DIRECTORY EXISTS"

		
		# CONVERTING JSON ARRAY OBJECT TO BASH OBJECT
		EXISTING_KP=$(aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' | jq -r '.[]')

		EXISTING_KP_NAME="none"

		echo "INFO ################### CHECKING ATLEAST ONE VALID KEY-PAIR IS PRESENT"

		for element1 in $EXISTING_KP; do

			for element2 in $(sudo ls /var/$KP_DIR); do

				if [[ "$element1" == "$(echo "$element2" | cut -d "." -f1)" ]]; then

					echo "INFO ################### VALID KEY-PAIR IS PRESENT IN THE SYSTEM"

					EXISTING_KP_NAME=$element1

					KP_NAME=$EXISTING_KP_NAME

					break

				fi
			done
		done

		# IF KEY-PAIR DOES'T EXIST THEN MAKE ANOTHER KEY-PAIR

		if [[ "$EXISTING_KP_NAME" == "none" ]]; then
			
			echo "INFO ################### VALID KEY-PAIR IS NOT PRESENT IN THE SYSTEM"

			echo "INFO ################### CREATING NEW KEY-PAIR AND ADDING IN KEY-PAIR DIRECTORY"

			aws ec2 create-key-pair --key-name "$KP_NAME" --key-type rsa --key-format pem  --query 'KeyMaterial' --output text | sudo tee /var/$KP_DIR/$KP_FILE > /dev/null

		fi

	else
		echo "INFO ################### KEY-PAIR DIRECTORY DOES NOT EXIST IN THE SYSTEM"

		############## MAKE DIRECTORY AND KEY-PAIR #############

		echo "INFO ################### MAKING KEY-PAIR DIRECTORY AND ADDING A VALID KEY-PAIR"

		sudo mkdir /var/$KP_DIR

		aws ec2 create-key-pair --key-name $KP_NAME --key-type rsa --key-format pem --query 'KeyMaterial' --output text | sudo tee /var/$KP_DIR/$KP_FILE > /dev/null
	fi

	echo "INFO ################### KEY-PAIR DETAILS"
	
	echo "INFO ################### KEY-PAIR NAME - $KP_NAME"
	
	echo "INFO ################### KEY-PAIR LOCATION - /var/$KP_DIR/$KP_NAME.pem"

	echo "INFO ################### GRANTING KEY READ ONLY PERMISSION TO OWNER FOR AUTO-SSH"

	sudo chmod 400 /var/$KP_DIR/"$KP_NAME".pem

	echo "INFO ################### KEY-PAIR DONE"

	echo "==================================================================================="
	
	#####################################################
	############ CREATING SECURITY GROUP ################
	#####################################################

	echo "INFO ################### SECURITY GROUP CREATION OR ALLOCATION"

	# DETERMINE LENGTH OF SECURITY GROUP ARRAY

	SEC_GRP_LEN=$(aws ec2 describe-security-groups | jq '.SecurityGroups | length')

	if [ "$SEC_GRP_LEN" -eq 1 ]; then

		echo "INFO ################### CUSTOM SECURITY GROUP DOES NOT EXIST"

		# MAKE SECURITY GROUP

		echo "INFO ################### MAKING CUSTOM SECURITY GROUP"

		SEC_GRP_ID=$(aws ec2 create-security-group --group-name $SEC_GRP_NAME --description "custom script security group" | jq '.GroupId')

		# NOW PROVIDE INGRESS RULES AS IT IS CREATED IN THE DEFAULT VPC NO NEED TO CREATE SSH PORT 22 RULE
		# PROVIDE TCP PORT 80 IPV4/V6 EVERYWHERE

		SEC_GRP_FORMAT=$(echo "$SEC_GRP_ID" | cut -d '"' -f2)


		echo "INFO ################### PROVIDING INGRESS RULES"

		# SSH
		aws ec2 authorize-security-group-ingress --group-id "$SEC_GRP_FORMAT" --protocol tcp --port 22 --cidr 0.0.0.0/0

		# IPV6
		aws ec2 authorize-security-group-ingress --group-id "$SEC_GRP_FORMAT" --ip-permissions '[{"IpProtocol": "tcp", "FromPort": 80, "ToPort": 80, "Ipv6Ranges": [{"CidrIpv6": "::/0"}]}]'

		# IPV4
		aws ec2 authorize-security-group-ingress --group-id "$SEC_GRP_FORMAT" --protocol tcp --port 80 --cidr 0.0.0.0/0

	else

		# REDIRECT DEC-SEC-GRP RESPOSE TO TEMP JSON FILE THEN PROCESS THAT FILE THROUGH JQ
		# CHECK IF ALREADY A SEC-GRP EXISTS WHICH HAS SAME INGRESS RULES

		echo "INFO ################### CUSTOM SECURITY GROUP EXISTS "

		touch $TMP_FILE
		
		# CONVERTING INTO JSON AND STORING IN TMP_FILE 

		echo "INFO ################### STORING RESPONSE IN TMP_FILE FOR FASTER PROCESSING"

		aws ec2 describe-security-groups | jq '.[]' > $TMP_FILE

		CHK_EXIST=false

		echo "INFO ################### CHECKING FOR VALID SECURITY GROUP"

		# MAIN LOOP
		for ((i = 0; i < $(jq '. | length' "$TMP_FILE"); i++)); do

			for ((j = 0; j < $(jq ".[$i].IpPermissions | length" "$TMP_FILE"); j++)); do
				
				FROM_PORT=$(jq ".[$i].IpPermissions[$j].FromPort" "$TMP_FILE")
				
				IP_PROTO=$(jq ".[$i].IpPermissions[$j].IpProtocol" "$TMP_FILE")

				IP_V4=$(jq ".[$i].IpPermissions[$j].IpRanges[0].CidrIp" "$TMP_FILE")
				
				IP_V6=$(jq ".[$i].IpPermissions[$j].Ipv6Ranges[0].CidrIpv6" "$TMP_FILE")

				if [[ "$FROM_PORT" == 80 && "$IP_PROTO" == '"tcp"' && "$IP_V4" == '"0.0.0.0/0"' && "$IP_V6" == '"::/0"' ]]; then

					echo "INFO ################### VALID SECURITY GROUP EXISTS"

					SEC_GRP_ID=$(jq ".[$i].GroupId" $TMP_FILE)
					
					SEC_GRP_FORMAT=$(echo "$SEC_GRP_ID" | cut -d '"' -f2)
					
					CHK_EXIST=true
					
					break 2

				fi

			done

		done
	
		if [ "$CHK_EXIST" == "false" ]; then
			
			echo "INFO ################### VALID SECURITY GROUP DOES NOT EXISTS"

			echo "INFO ################### MAKING VALID SECURITY GROUP"

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
	
	echo "INFO ################### VALID SECURITY GROUP ID - $SEC_GRP_FORMAT"

	echo "INFO ################### SECURITY GROUP PROCESS DONE"

	echo "==================================================================================="
	
	echo "INFO ################### CREATING UBUNTU SERVER 22.04 LTS"
	
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

		echo "INFO ################### UBUNTU SERVER 22.04 LTS SERVER CREATED SUCCESSFULLY"

		echo "INFO ################### SERVER INSTANCE ID - $INS_ID"

	else 

		echo "ERROR ################### SERVER NOT ABLE TO CREATE"
		exit 2 
	fi

	echo "==================================================================================="

}

processInstallation() {


	echo "INFO ################### INSTALLATION PROCESS STARTING"

	FOR_INS_ID=$(echo "$1" | cut -d '"' -f2)

	HOST=$(aws ec2 describe-instances --instance-ids "$FOR_INS_ID" | jq '.Reservations[].Instances[].PublicDnsName' | cut -d '"' -f2)

	KEY="/var/$KP_DIR/$2.pem"

	LINK_FILE="link_file.txt"

	BASH_FILE="commands.sh"

	echo "INFO ################### TARGET INSTANCE-ID - $FOR_INS_ID TARGET HOST - $HOST TARGET KEY - $KEY"
	
	############# ASK USER WHICH WEBSITE TO HOST #############
	echo ""

while true; do

    cat << EOF

    ENTER WHICH WEBSITE TO HOST :::

    PRESS 1 TO BARISTA CAFE (YOUR CAFE TYPE WEBSITE)

    PRESS 2 TO MINI FINANCE (YOUR MINI CAFE WEBSITE)

    PRESS 3 TO WEDDING LITE (YOUR WEDDING TYPE)

    PRESS 4 TO MOSO INTERIOR (YOUR INTERIOR BUISNESS)

    PRESS 5 TO JOB SEARCH (SOME JOB-SEARCH WEBSITE)

EOF

    read -p "ENTER YOUR CHOICE (1-5): " choice

    case $choice in
        1)
            echo "YOU SELECTED CAFE WEBSITE."
			echo "https://www.tooplate.com/zip-templates/2137_barista_cafe.zip" > $LINK_FILE
            break
            ;;
        2)
            echo "YOU SELECTED MINI FINANCE."
			echo "https://www.tooplate.com/zip-templates/2135_mini_finance.zip" > $LINK_FILE
            break
            ;;
        3)
            echo "YOU SELECTED WEDDING LITE."
			echo "https://www.tooplate.com/zip-templates/2131_wedding_lite.zip" > $LINK_FILE
            break
            ;;
        4)
            echo "YOU SELECTED MOSO INTERIOR."
			echo "https://www.tooplate.com/zip-templates/2133_moso_interior.zip" > $LINK_FILE

            break
            ;;
        5)
            echo "YOU SELECTED JOB SEARCH."
			echo "https://www.tooplate.com/zip-templates/2134_gotto_job.zip" > $LINK_FILE

            break
            ;;
        *)
            echo "WARNING ################### INVALID CHOICE. PLEASE ENTER A NUMBER BETWEEN 1 AND 5."
            ;;
    esac
done

echo "INFO ################### CREATING COMMANDS WHICH CAN BE EXECUTED IN REMOTE MACHINE"

cat << EOF > $BASH_FILE

#!/bin/bash

if [ -e $REM_STATUS_FILE ]; then

# MAIN PROCESS 

curl -O $(cat $LINK_FILE)

unzip $(cat $LINK_FILE | cut -d "/" -f5)

sudo rm -rf /var/www/html/*

sudo rsync -av --remove-source-files $(cat $LINK_FILE | cut -d "/" -f5 | cut -d "." -f1)/* /var/www/html/

sudo systemctl restart apache2 

# CLEANING 

rm -rf $(cat $LINK_FILE | cut -d "/" -f5)

rm -rf $(cat $LINK_FILE | cut -d "/" -f5 | cut -d "." -f1)

rm -rf $LINK_FILE

else

# SYSTEM UPDATION AND APACHE2 SERVER INSTALLATION 

sudo apt update -y ; sudo apt upgrade -y

sudo apt install apache2 zip unzip -y

sudo systemctl start apache2 

sudo systemctl enable apache2

# SOFTWARE INSTALLATION - HTMLQ TO EXTRACT TEXT FROM HTML TEMPLATES 

sudo curl -L --output htmlq.tar.gz $HTMLQ_LINK

sudo tar xf htmlq.tar.gz -C /usr/local/bin

rm -rf htmlq.tar.gz

# MAIN PROCESS 

curl -O $(cat $LINK_FILE)

unzip $(cat $LINK_FILE | cut -d "/" -f5)

sudo rm -rf /var/www/html/*

sudo rsync -av --remove-source-files $(cat $LINK_FILE | cut -d "/" -f5 | cut -d "." -f1)/* /var/www/html/

sudo systemctl restart apache2 

# CLEAN-UP

rm -rf $(cat $LINK_FILE | cut -d "/" -f5)

rm -rf $(cat $LINK_FILE | cut -d "/" -f5 | cut -d "." -f1)

rm -rf $LINK_FILE

# STORING THE NAME OF WEB-SITE HOSTED IN A TEXT FILE BY EXTRACTING HTML <title> FIELD 

sudo curl -s localhost | htmlq --text title | cut -d "-" -f1 | sudo tee $REM_STATUS_FILE > /dev/null

fi

EOF

	echo "INFO ################### TRYING TO TRANSFER FILES THROUGH SSH SCP"

	scp_count=0

	while true; do

		sudo scp -o BatchMode=yes -o StrictHostKeyChecking=no -i "$KEY" $LINK_FILE $BASH_FILE $USER@"$HOST":~/ > /dev/null 
		
		if [[ $? -eq 0 ]]; then 

			echo "INFO ################### FILES TRANSFERRED SUCCESSFULLY"

			break
		fi

		if [[ $scp_count -eq 10 ]]; then 

			echo "ERROR ################### FILES CANNOT BE TRANSFERRED"
			exit 1
		fi
		
		((scp_count++))

	done

	# BASH FILE CLEAN-UP 
	sudo rm -rf $BASH_FILE $LINK_FILE

########### HERE WE WILL GET INSTANCE ID ############ 
# 1. SSH INTO THE MACHINE THROUGH PEM KEY
# 2. AND EXECUTE COMMANDS THROUGH BASH FILE WHICH IS TRANSFERRED

echo "INFO ################### TRYING TO SSH INTO MACHINE AND EXECUTING COMMANDS"

echo "INFO ################### PLEASE BE PATIENT AS THIS PROCESS MAY TAKE FEW MINUTES ..... "
	
sudo ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i "$KEY" $USER@"$HOST" << EOF > /dev/null 2>&1

sudo chmod u+x $BASH_FILE
./$BASH_FILE

EOF

	PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$FOR_INS_ID" | jq '.Reservations[].Instances[].PublicIpAddress')
	
	# STATUS_CODE=$(curl -s -I "$PUBLIC_IP" | awk 'NR==1{print $2}' &> /dev/null)

	# IMPLEMENT LOGIC MATCH THE TITLE OF THE HTML WEBSITE WITH THE /OPT/BUILT_FILE.TXT 
	# IF THEY BOTH MATCHES THEN THEY ARE 101% CORRECT WEBSITE HOSTED 


	echo "INFO ################### SUCESS !!! PLEASE ACCESS YOUR WEBSITE AT - $PUBLIC_IP"



}


checkIfWebHosted() {

	# check for any website hosted in this instance 
	# parameters :: 1-keypath ; 2-user ; 3-host ; 4-public ip

	sudo ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i "$1" "$2"@"$3" << EOF > /dev/null 2>&1 

	if [ ! -f $REM_STATUS_FILE ]; then 
		exit 101
	fi

EOF

	STATUS_FLAG="NO"
	if [ $? -eq 0 ]; then

		# YES WEBSITE IS HOSTED IN THE INSTANCE 
		# FIND THE NAME OF THE WEBSITE HOSTED USING PUBLIC IP ADDRESS 

		STATUS_FLAG="YES"

		WEBSITE_NAME=$(curl -s "$4" | htmlq --text title | cut -d "-" -f1 | tr '[:lower:]' '[:upper:]')

	fi

}


############## CHECK HOW MANY INTANCES ARE PRESENT #######################
# IF -- RESERVATION COUNT IS 0 THEN CREATE NEW INSTANCE WITH ABOVE DETAILS AND DO THE FURTHER PROCESS 
# IF -- RESERVATION COUNT IS >= 1 THEN CHECK KEY-PAIR NAME AND IP_PERMISSIONS 
#	IF BOTH ARE SATISFIED THEN CHECK THE STATUS OF VM IF IT IS STOPPED THEN TURN ON AND DO THE FURTHER PROCESS 
#   ELSE THEN CREATE A NEW VM AND DO THE FURTHER PROCESS 
############## NOW CREATE INSTANCE WITH THE ABOVE DETAILS ################ 

# CHECK NUMBER OF RUNNING AND STOPPED INSTANCES 

INS_NUM=$(aws ec2 describe-instances --filters "Name=instance-state-name,Values=running,stopped" --query "Reservations[*].Instances[*].{Instance:InstanceId,State:State.Name}" | jq '. | length')

if [[ $INS_NUM -eq 0 ]]; then 

	# THIS CONDITION IS FOR NEW INSTANCE CREATION FROM SCRATCH 

	echo "INFO ################### THERE ARE NO RUNNING OR STOPPED INSTANCES CURRENT IN YOUR AWS EC2"
	newIns

	echo "INFO ################### WAITING FOR INSTACE TO BE IN RUNNING STATE"
	
	# CONTINUE FURTHER ONLY IF THE INTANCE STATE IS IN RUNNING STATE 
	while true; do

		RES_LEN=$(aws ec2 describe-instances --instance-ids "$FOR_INS_ID" --filters "Name=instance-state-name,Values=running" | jq '.Reservations | length')

		if [ "$RES_LEN" -gt 0 ]; then
			
			processInstallation "$INS_ID" "$KP_NAME"
			break

		fi

	done


else

	echo "INFO ################### THERE ARE $INS_NUM RUNNING OR STOPPED INSTANCES CURRENT IN YOUR AWS EC2"

	: '
		0. LIST ALL ACTIVE AND STOPPED INSTANCE
		1, CHOOSE WHICH INSTANCE TO SELECT 
		2. CHECK IF THAT INSTANCE HAS APACHE SERVICE HOSTED AND WEBSITE RUNNING 
		3. ASK USER TO RE-HOST SOME OTHER WEBSITE ; IF YES THEN CONTINUE PROCESS INSTALLATION PROCESS ; IF NOT THEN SPIT OUT PUBLIC IP 
		4. THEN CHECK IF THAT INSTACE WAS RUNNING OR STOPPED ; IF STOPPED THEN PROMT USER IF HE WANTS TO RUN ; IF YES THEN 

	'

	: '

		MEANING OF VALID INSTANCE : THAT INSTANCE WHICH HAS IPV4/V6 EVERYWHERE AND KEY-PAIR IS PRESENT IN THE SYSTEM 
		
		OS DEPENDENT - Ubuntu 22.04 


	'

	TMP_FILE="/tmp/instance_list.json"

	aws ec2 describe-instances | jq '.' > $TMP_FILE

	echo "INFO ################### CHECKING FOR VALID INSTANCES ...."

	for (( i = 0; i < "$INS_NUM"; i++ )); do
			
		SEC_ID=$(jq ".Reservations[$i].Instances[].SecurityGroups[].GroupId" $TMP_FILE | cut -d '"' -f2)

		INS_KP=$(jq ".Reservations[$i].Instances[].KeyName" $TMP_FILE | cut -d '"' -f2)

		IP_V4=$(aws ec2 describe-security-groups --group-ids "$SEC_ID" | jq -r '.SecurityGroups[].IpPermissions[] | select(.IpProtocol=="tcp" and .FromPort==80)' | jq '.IpRanges[].CidrIp')

		IP_V6=$(aws ec2 describe-security-groups --group-ids "$SEC_ID" | jq -r '.SecurityGroups[].IpPermissions[] | select(.IpProtocol=="tcp" and .FromPort==80)' | jq '.Ipv6Ranges[].CidrIpv6')

		INS_ID=$(jq ".Reservations[$i].Instances[].InstanceId" $TMP_FILE)

		AMI_IMG=$(jq ".Reservations[$i].Instances[].ImageId" $TMP_FILE)
		
		if [[ $IP_V4 == '"0.0.0.0/0"' && $IP_V6 == '"::/0"' && $AMI_IMG == '"ami-0c7217cdde317cfec"' ]] && [ -f "/var/$KP_DIR/$INS_KP.pem" ]; then

			echo "INFO ################### FOUND VALID INSTANCE"
			echo "INFO ################### CHECKING IF ANY WEBSITE IS HOSTED IN THIS INSTACE"

			HOST=$(jq ".Reservations[$i].Instances[].PublicDnsName" $TMP_FILE | cut -d '"' -f2)
			
			KEY=/var/$KP_DIR/$INS_KP.pem
			
			PUBLIC_IP=$(jq ".Reservations[$i].Instances[].PublicIpAddress" $TMP_FILE | cut -d '"' -f2)


			# WEBSITE CHECK START 
			
			checkIfWebHosted "$KEY" $USER "$HOST" "$PUBLIC_IP"
			
			# WEBSITE CHECK DONE 

			if [ $STATUS_FLAG == "YES" ]; then 

				echo "INFO ################### $WEBSITE_NAME WEBSITE IS HOSTED AT $PUBLIC_IP"

				while true; do 

		echo -e "
			
		PRESS 1 TO RE-HOST WITH SOME OTHER WEBSITE \n  
		PRESS 2 TO MAKE ANOTHER WEB-SITE WITH NEW INSTANCE \n  
		PRESS 3 TO DO-NOTHING \n  

		"
					read -p "ENTER YOUR CHOICE (1-3): " input 

					case $input in

						1)
						
            				echo "INFO ################### RE-HOSTING PROCESS BEGGINNING .... "
							processInstallation "$INS_ID" "$INS_KP"
							break 
							;;

						2)


							newIns
							break 
							;;
						
						3)

							echo "INFO ################### $WEBSITE_NAME WEBSITE IS HOSTED AT $PUBLIC_IP"
							break
							;;

						*)
            				echo "WARNING ################### INVALID CHOICE. PLEASE ENTER A NUMBER BETWEEN 1 AND 3."
					
					esac

				done
			
			fi
		
		fi	

	done
	
fi