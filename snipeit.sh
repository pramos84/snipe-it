#!/bin/bash

######################################################
#           Snipe-It Install Script                  #
#          Script created by Mike Tucker             #
#            mtucker6784@gmail.com                   #
# This script is just to help streamline the         #
# install process for Debian and CentOS              #
# based distributions. I assume you will be          #
# installing as a subdomain on a fresh OS install.   #
# Right now I'm not going to worry about SMTP setup  #
#                                                    #
# Feel free to modify, but please give               #
# credit where it's due. Thanks!                     #
######################################################

# ensure running as root
if [ "$(id -u)" != "0" ]; then
  exec sudo "$0" "$@"
fi
#First things first, let's set some variables and find our distro.
clear

name="snipeit"
si="Snipe-IT"
hostname="$(hostname)"
fqdn="$(hostname --fqdn)"
ans=default
hosts=/etc/hosts
file=master.zip
tmp=/tmp/$name

rm -rf $tmp/
mkdir $tmp

function isinstalled {
  if yum list installed "$@" >/dev/null 2>&1; then
    true
  else
    false
  fi
}


#  Lets find what distro we are using and what version
distro="$(cat /proc/version)"
if grep -q centos <<<$distro; then
	for f in $(find /etc -type f -maxdepth 1 \( ! -wholename /etc/os-release ! -wholename /etc/lsb-release -wholename /etc/\*release -o -wholename /etc/\*version \) 2> /dev/null);
	do
		distro="${f:5:${#f}-13}"
	done;
	if [ "$distro" = "centos" ] || [ "$distro" = "redhat" ]; then
		distro+="$(rpm -q --qf "%{VERSION}" $(rpm -q --whatprovides redhat-release))"
	fi
fi

echo "
	   _____       _                  __________
	  / ___/____  (_)___  ___        /  _/_  __/
	  \__ \/ __ \/ / __ \/ _ \______ / /  / /
	 ___/ / / / / / /_/ /  __/_____// /  / /
	/____/_/ /_/_/ .___/\___/     /___/ /_/
	            /_/
"

echo ""
echo ""
echo "  Welcome to Snipe-IT Inventory Installer for Centos and Debian!"
echo ""

case $distro in
        *Ubuntu*)
                echo "  The installer has detected Ubuntu as the OS."
                distro=ubuntu
                ;;
	*Debian*)
                echo "  The installer has detected Debian as the OS."
                distro=debian
                ;;
        *centos6*|*redhat6*)
                echo "  The installer has detected $distro as the OS."
                distro=centos6
                ;;
        *centos7*|*redhat7*)
                echo "  The installer has detected $distro as the OS."
                distro=centos7
                ;;
        *)
                echo "  The installer was unable to determine your OS. Exiting for safety."
                exit
                ;;
esac

#Get your FQDN.

echo -n "  Q. What is the FQDN of your server? ($fqdn): "
read fqdn
if [ -z "$fqdn" ]; then
        fqdn="$(hostname --fqdn)"
fi
echo "     Setting to $fqdn"
echo ""

#Do you want to set your own passwords, or have me generate random ones?
until [[ $ans == "yes" ]] || [[ $ans == "no" ]]; do
echo -n "  Q. Do you want me to automatically create the snipe database user password? (y/n) "
read setpw

case $setpw in
        [yY] | [yY][Ee][Ss] )
                mysqluserpw="$(echo `< /dev/urandom tr -dc _A-Za-z-0-9 | head -c16`)"
                ans="yes"
                ;;
        [nN] | [n|N][O|o] )
                echo -n  "  Q. What do you want your snipeit user password to be?"
                read -s mysqluserpw
                echo ""
				ans="no"
                ;;
        *) 		echo "  Invalid answer. Please type y or n"
                ;;
esac
done

#Snipe says we need a new 32bit key, so let's create one randomly and inject it into the file
random32="$(echo `< /dev/urandom tr -dc _A-Za-z-0-9 | head -c32`)"

#db_setup.sql will be injected to the database during install.
#Again, this file should be removed, which will be a prompt at the end of the script.
dbsetup=$tmp/db_setup.sql
echo >> $dbsetup "CREATE DATABASE snipeit;"
echo >> $dbsetup "GRANT ALL PRIVILEGES ON snipeit.* TO snipeit@localhost IDENTIFIED BY '$mysqluserpw';"

#Let us make it so only root can read the file. Again, this isn't best practice, so please remove these after the install.
chown root:root $dbsetup
chmod 700 $dbsetup

## TODO: Progress tracker on each step

case $distro in
	debian)
		#####################################  Install for Debian ##############################################

		webdir=/var/www

		#Update/upgrade Debian repositories.
		echo ""
		echo "##  Updating Debian packages in the background. Please be patient."
		echo ""
		apachefile=/etc/apache2/sites-available/$name.conf
		sudo apt-get update >> /var/log/snipeit-install.log 2>&1
		sudo apt-get -y upgrade >> /var/log/snipeit-install.log 2>&1

		echo "##  Installing packages."
		sudo apt-get -y install mariadb-server mariadb-client
		echo "## Going to suppress more messages that you don't need to worry about. Please wait."
		sudo apt-get -y install apache2 >> /var/log/snipeit-install.log 2>&1
		sudo apt-get install -y git unzip php5 php5-mcrypt php5-curl php5-mysql php5-gd php5-ldap libapache2-mod-php5 curl >> /var/log/snipeit-install.log 2>&1
		sudo service apache2 restart
		
		#We already established MySQL root & user PWs, so we dont need to be prompted. Let's go ahead and install Apache, PHP and MySQL.
		echo "##  Setting up LAMP."
		#sudo DEBIAN_FRONTEND=noninteractive apt-get install -y lamp-server^ >> /var/log/snipeit-install.log 2>&1 

		#  Get files and extract to web dir
		echo ""
		echo "##  Downloading snipeit and extract to web directory."
		wget -P $tmp/ https://github.com/snipe/snipe-it/archive/$file >> /var/log/snipeit-install.log 2>&1 
		unzip -qo $tmp/$file -d $tmp/
		cp -R $tmp/snipe-it-master $webdir/$name

		##  TODO make sure apache is set to start on boot and go ahead and start it

		#Enable mcrypt and rewrite
		echo "##  Enabling mcrypt and rewrite"
		sudo php5enmod mcrypt >> /var/log/snipeit-install.log 2>&1 
		sudo a2enmod rewrite >> /var/log/snipeit-install.log 2>&1 
		sudo ls -al /etc/apache2/mods-enabled/rewrite.load >> /var/log/snipeit-install.log 2>&1 

		#Create a new virtual host for Apache.
		echo "##  Create Virtual host for apache."
		echo >> $apachefile ""
		echo >> $apachefile ""
		echo >> $apachefile "<VirtualHost *:80>"
		echo >> $apachefile "ServerAdmin webmaster@localhost"
		echo >> $apachefile "    <Directory $webdir/$name/public>"
		echo >> $apachefile "        Require all granted"
		echo >> $apachefile "        AllowOverride All"
		echo >> $apachefile "   </Directory>"
		echo >> $apachefile "    DocumentRoot $webdir/$name/public"
		echo >> $apachefile "    ServerName $fqdn"
		echo >> $apachefile "        ErrorLog /var/log/apache2/snipeIT.error.log"
		echo >> $apachefile "        CustomLog /var/log/apache2/access.log combined"
		echo >> $apachefile "</VirtualHost>"

		echo "##  Setting up hosts file."
		echo >> $hosts "127.0.0.1 $hostname $fqdn"
		a2ensite $name.conf >> /var/log/snipeit-install.log 2>&1 

		#Modify the Snipe-It files necessary for a production environment.
		echo "##  Modify the Snipe-It files necessary for a production environment."
		echo "	Setting up Timezone."
		tzone=$(cat /etc/timezone);
		sed -i "s,UTC,$tzone,g" $webdir/$name/app/config/app.php

		echo "	Setting up bootstrap file."
		sed -i "s,www.yourserver.com,$hostname,g" $webdir/$name/bootstrap/start.php

		echo "	Setting up database file."
		cp $webdir/$name/app/config/production/database.example.php $webdir/$name/app/config/production/database.php
		sed -i "s,snipeit_laravel,snipeit,g" $webdir/$name/app/config/production/database.php
		sed -i "s,travis,snipeit,g" $webdir/$name/app/config/production/database.php
		sed -i "s,password'  => '',password'  => '$mysqluserpw',g" $webdir/$name/app/config/production/database.php

		echo "	Setting up app file."
		cp $webdir/$name/app/config/production/app.example.php $webdir/$name/app/config/production/app.php
		sed -i "s,production.yourserver.com,$fqdn,g" $webdir/$name/app/config/production/app.php
		sed -i "s,Change_this_key_or_snipe_will_get_ya,$random32,g" $webdir/$name/app/config/production/app.php
		## from mtucker6784: Is there a particular reason we want end users to have debug mode on with a fresh install?
		#sed -i "s,false,true,g" $webdir/$name/app/config/production/app.php

		echo "	Setting up mail file."
		cp $webdir/$name/app/config/production/mail.example.php $webdir/$name/app/config/production/mail.php

		##  TODO make sure mysql is set to start on boot and go ahead and start it

		#Change permissions on directories
		echo "##  Seting permissions on web directory."
		sudo chmod -R 755 $webdir/$name/app/storage
		sudo chmod -R 755 $webdir/$name/app/private_uploads
		sudo chmod -R 755 $webdir/$name/public/uploads
		sudo chown -R www-data:www-data /var/www/
		# echo "##  Finished permission changes."
		
		echo "##  Input your MySQL/MariaDB root password: "
		echo ""
		sudo mysql -u root -p < $dbsetup
		echo ""
		
		echo "##  Securing Mysql"
		echo "## I understand this is redundant. You don't need to change your root pw again if you don't want to."
		# Have user set own root password when securing install
		# and just set the snipeit database user at the beginning
		/usr/bin/mysql_secure_installation

		#Install / configure composer
		echo "##  Installing and configuring composer"
		curl -sS https://getcomposer.org/installer | php
		mv composer.phar /usr/local/bin/composer
		cd $webdir/$name/
		composer install --no-dev --prefer-source
		php artisan app:install --env=production

		echo "##  Restarting apache."
		service apache2 restart
		;;
		
	ubuntu)
		#####################################  Install for Ubuntu  ##############################################

		webdir=/var/www

		#Update/upgrade Debian/Ubuntu repositories, get the latest version of git.
		echo ""
		echo "##  Updating ubuntu in the background. Please be patient."
		echo ""
		apachefile=/etc/apache2/sites-available/$name.conf
		sudo apt-get update >> /var/log/snipeit-install.log 2>&1
		sudo apt-get -y upgrade >> /var/log/snipeit-install.log 2>&1

		echo "##  Installing packages."
		sudo apt-get install -y git unzip php5 php5-mcrypt php5-curl php5-mysql php5-gd php5-ldap >> /var/log/snipeit-install.log 2>&1 
		#We already established MySQL root & user PWs, so we dont need to be prompted. Let's go ahead and install Apache, PHP and MySQL.
		echo "##  Setting up LAMP."
		sudo DEBIAN_FRONTEND=noninteractive apt-get install -y lamp-server^ >> /var/log/snipeit-install.log 2>&1 

		#  Get files and extract to web dir
		echo ""
		echo "##  Downloading snipeit and extract to web directory."
		wget -P $tmp/ https://github.com/snipe/snipe-it/archive/$file >> /var/log/snipeit-install.log 2>&1 
		unzip -qo $tmp/$file -d $tmp/
		cp -R $tmp/snipe-it-master $webdir/$name

		##  TODO make sure apache is set to start on boot and go ahead and start it

		#Enable mcrypt and rewrite
		echo "##  Enabling mcrypt and rewrite"
		sudo php5enmod mcrypt >> /var/log/snipeit-install.log 2>&1 
		sudo a2enmod rewrite >> /var/log/snipeit-install.log 2>&1 
		sudo ls -al /etc/apache2/mods-enabled/rewrite.load >> /var/log/snipeit-install.log 2>&1 

		#Create a new virtual host for Apache.
		echo "##  Create Virtual host for apache."
		echo >> $apachefile ""
		echo >> $apachefile ""
		echo >> $apachefile "<VirtualHost *:80>"
		echo >> $apachefile "ServerAdmin webmaster@localhost"
		echo >> $apachefile "    <Directory $webdir/$name/public>"
		echo >> $apachefile "        Require all granted"
		echo >> $apachefile "        AllowOverride All"
		echo >> $apachefile "   </Directory>"
		echo >> $apachefile "    DocumentRoot $webdir/$name/public"
		echo >> $apachefile "    ServerName $fqdn"
		echo >> $apachefile "        ErrorLog /var/log/apache2/snipeIT.error.log"
		echo >> $apachefile "        CustomLog /var/log/apache2/access.log combined"
		echo >> $apachefile "</VirtualHost>"

		echo "##  Setting up hosts file."
		echo >> $hosts "127.0.0.1 $hostname $fqdn"
		a2ensite $name.conf >> /var/log/snipeit-install.log 2>&1 

		#Modify the Snipe-It files necessary for a production environment.
		echo "##  Modify the Snipe-It files necessary for a production environment."
		echo "	Setting up Timezone."
		tzone=$(cat /etc/timezone);
		sed -i "s,UTC,$tzone,g" $webdir/$name/app/config/app.php

		echo "	Setting up bootstrap file."
		sed -i "s,www.yourserver.com,$hostname,g" $webdir/$name/bootstrap/start.php

		echo "	Setting up database file."
		cp $webdir/$name/app/config/production/database.example.php $webdir/$name/app/config/production/database.php
		sed -i "s,snipeit_laravel,snipeit,g" $webdir/$name/app/config/production/database.php
		sed -i "s,travis,snipeit,g" $webdir/$name/app/config/production/database.php
		sed -i "s,password'  => '',password'  => '$mysqluserpw',g" $webdir/$name/app/config/production/database.php

		echo "	Setting up app file."
		cp $webdir/$name/app/config/production/app.example.php $webdir/$name/app/config/production/app.php
		sed -i "s,production.yourserver.com,$fqdn,g" $webdir/$name/app/config/production/app.php
		sed -i "s,Change_this_key_or_snipe_will_get_ya,$random32,g" $webdir/$name/app/config/production/app.php
		## from mtucker6784: Is there a particular reason we want end users to have debug mode on with a fresh install?
		#sed -i "s,false,true,g" $webdir/$name/app/config/production/app.php

		echo "	Setting up mail file."
		cp $webdir/$name/app/config/production/mail.example.php $webdir/$name/app/config/production/mail.php

		##  TODO make sure mysql is set to start on boot and go ahead and start it

		#Change permissions on directories
		echo "##  Seting permissions on web directory."
		sudo chmod -R 755 $webdir/$name/app/storage
		sudo chmod -R 755 $webdir/$name/app/private_uploads
		sudo chmod -R 755 $webdir/$name/public/uploads
		sudo chown -R www-data:www-data /var/www/
		# echo "##  Finished permission changes."

		echo "##  Input your MySQL/MariaDB root password: "
		sudo mysql -u root -p < $dbsetup

		echo "##  Securing Mysql"

		# Have user set own root password when securing install
		# and just set the snipeit database user at the beginning
		/usr/bin/mysql_secure_installation

		#Install / configure composer
		echo "##  Installing and configuring composer"
		curl -sS https://getcomposer.org/installer | php
		mv composer.phar /usr/local/bin/composer
		cd $webdir/$name/
		composer install --no-dev --prefer-source
		php artisan app:install --env=production

		echo "##  Restarting apache."
		service apache2 restart
		;;
	centos6 )
		#####################################  Install for Centos/Redhat 6  ##############################################

		webdir=/var/www/html

##TODO make sure the repo doesnt exhist isnt already in there

		#Allow us to get the mysql engine
		echo ""
		echo "##  Adding IUS, epel-release and mariaDB repos.";
		mariadbRepo=/etc/yum.repos.d/MariaDB.repo
		touch $mariadbRepo
		echo >> $mariadbRepo "[mariadb]"
		echo >> $mariadbRepo "name = MariaDB"
		echo >> $mariadbRepo "baseurl = http://yum.mariadb.org/10.0/centos6-amd64"
		echo >> $mariadbRepo "gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB"
		echo >> $mariadbRepo "gpgcheck=1"
		echo >> $mariadbRepo "enable=1"

		yum -y install wget epel-release >> /var/log/snipeit-install.log 2>&1 
		wget -P $tmp/ https://centos6.iuscommunity.org/ius-release.rpm >> /var/log/snipeit-install.log 2>&1 
		rpm -Uvh $tmp/ius-release*.rpm >> /var/log/snipeit-install.log 2>&1 


		#Install PHP and other needed stuff.
		echo "##  Installing PHP and other needed stuff";
		PACKAGES="httpd MariaDB-server git unzip php56u php56u-mysqlnd php56u-bcmath php56u-cli php56u-common php56u-embedded php56u-gd php56u-mbstring php56u-mcrypt php56u-ldap"

		for p in $PACKAGES;do
			if isinstalled $p;then
				echo " ##" $p "Installed"
			else
				echo -n " ##" $p "Installing... "
				yum -y install $p >> /var/log/snipeit-install.log 2>&1 
				echo "";
			fi
		done;

        echo ""
		echo "##  Downloading Snipe-IT from github and putting it in the web directory.";

		wget -P $tmp/ https://github.com/snipe/snipe-it/archive/$file >> /var/log/snipeit-install.log 2>&1 
		unzip -qo $tmp/$file -d $tmp/
		cp -R $tmp/snipe-it-master $webdir/$name

		# Make mariaDB start on boot and restart the daemon
		echo "##  Starting the mariaDB server.";
		chkconfig mysql on
		/sbin/service mysql start

		echo "##  Input your MySQL/MariaDB root password: "
		mysql -u root < $dbsetup

		echo "##  Securing mariaDB server.";
		/usr/bin/mysql_secure_installation

##TODO make sure the apachefile doesnt exhist isnt already in there
		#Create the new virtual host in Apache and enable rewrite
		echo "##  Creating the new virtual host in Apache.";
		apachefile=/etc/httpd/conf.d/$name.conf

		echo >> $apachefile ""
		echo >> $apachefile ""
		echo >> $apachefile "LoadModule rewrite_module modules/mod_rewrite.so"
		echo >> $apachefile ""
		echo >> $apachefile "<VirtualHost *:80>"
		echo >> $apachefile "ServerAdmin webmaster@localhost"
		echo >> $apachefile "    <Directory $webdir/$name/public>"
		echo >> $apachefile "        Allow From All"
		echo >> $apachefile "        AllowOverride All"
		echo >> $apachefile "        Options +Indexes"
		echo >> $apachefile "   </Directory>"
		echo >> $apachefile "    DocumentRoot $webdir/$name/public"
		echo >> $apachefile "    ServerName $fqdn"
		echo >> $apachefile "        ErrorLog /var/log/httpd/snipeIT.error.log"
		echo >> $apachefile "        CustomLog /var/log/access.log combined"
		echo >> $apachefile "</VirtualHost>"

##TODO make sure hosts file doesnt already contain this info
		echo "##  Setting up hosts file.";
		echo >> $hosts "127.0.0.1 $hostname $fqdn"

		# Make apache start on boot and restart the daemon
		echo "##  Starting the apache server.";
		chkconfig httpd on
		/sbin/service httpd start

		#Modify the Snipe-It files necessary for a production environment.
		echo "##  Modifying the Snipe-It files necessary for a production environment."
		echo "	Setting up Timezone."
		tzone=$(grep ZONE /etc/sysconfig/clock | tr -d '"' | sed 's/ZONE=//g');
		sed -i "s,UTC,$tzone,g" $webdir/$name/app/config/app.php

		echo "	Setting up bootstrap file."
		sed -i "s,www.yourserver.com,$hostname,g" $webdir/$name/bootstrap/start.php

		echo "	Setting up database file."
		cp $webdir/$name/app/config/production/database.example.php $webdir/$name/app/config/production/database.php
		sed -i "s,snipeit_laravel,snipeit,g" $webdir/$name/app/config/production/database.php
		sed -i "s,travis,snipeit,g" $webdir/$name/app/config/production/database.php
		sed -i "s,password'  => '',password'  => '$mysqluserpw',g" $webdir/$name/app/config/production/database.php

		echo "	Setting up app file."
		cp $webdir/$name/app/config/production/app.example.php $webdir/$name/app/config/production/app.php
		sed -i "s,production.yourserver.com,$fqdn,g" $webdir/$name/app/config/production/app.php
		sed -i "s,Change_this_key_or_snipe_will_get_ya,$random32,g" $webdir/$name/app/config/production/app.php
		## from mtucker6784: Is there a particular reason we want end users to have debug mode on with a fresh install?
		#sed -i "s,false,true,g" $webdir/$name/app/config/production/app.php

		echo "	Setting up mail file."
		cp $webdir/$name/app/config/production/mail.example.php $webdir/$name/app/config/production/mail.php

		# Change permissions on directories
		sudo chmod -R 755 $webdir/$name/app/storage
		sudo chmod -R 755 $webdir/$name/app/private_uploads
		sudo chmod -R 755 $webdir/$name/public/uploads
		sudo chown -R apache:apache $webdir/$name

		#Install / configure composer
		echo "##  Configure composer"
		cd $webdir/$name
		curl -sS https://getcomposer.org/installer | php
		php composer.phar install --no-dev --prefer-source

		echo "##  Installing Snipe-IT"
		php artisan app:install --env=production

#TODO detect if SELinux and firewall are enabled to decide what to do
		#Add SELinux and firewall exception/rules. Youll have to allow 443 if you want ssl connectivity.
		# chcon -R -h -t httpd_sys_script_rw_t $webdir/$name/
		# firewall-cmd --zone=public --add-port=80/tcp --permanent
		# firewall-cmd --reload

		service httpd restart
		;;
	centos7 )
		#####################################  Install for Centos/Redhat 7  ##############################################

		webdir=/var/www/html

		#Allow us to get the mysql engine
		echo ""
		echo "##  Add IUS, epel-release and mariaDB repos.";
		yum -y install wget epel-release >> /var/log/snipeit-install.log 2>&1 
		wget -P $tmp/ https://centos7.iuscommunity.org/ius-release.rpm >> /var/log/snipeit-install.log 2>&1 
		rpm -Uvh $tmp/ius-release*.rpm >> /var/log/snipeit-install.log 2>&1 

		#Install PHP and other needed stuff.
		echo "##  Installing PHP and other needed stuff";
		PACKAGES="httpd mariadb-server git unzip php56u php56u-mysqlnd php56u-bcmath php56u-cli php56u-common php56u-embedded php56u-gd php56u-mbstring php56u-mcrypt php56u-ldap"

		for p in $PACKAGES;do
			if isinstalled $p;then
				echo " ##" $p "Installed"
			else
				echo -n " ##" $p "Installing... "
				yum -y install $p >> /var/log/snipeit-install.log 2>&1 
			echo "";
			fi
		done;

        echo ""
		echo "##  Downloading Snipe-IT from github and put it in the web directory.";

		wget -P $tmp/ https://github.com/snipe/snipe-it/archive/$file >> /var/log/snipeit-install.log 2>&1 
		unzip -qo $tmp/$file -d $tmp/
		cp -R $tmp/snipe-it-master $webdir/$name

		# Make mariaDB start on boot and restart the daemon
		echo "##  Starting the mariaDB server.";
		systemctl enable mariadb.service
		systemctl start mariadb.service

		echo "##  Input your MySQL/MariaDB root password "
		mysql -u root -p < $dbsetup

		echo "##  Securing mariaDB server.";
		echo "";
		echo "";
		/usr/bin/mysql_secure_installation


##TODO make sure the apachefile doesnt exhist isnt already in there
		#Create the new virtual host in Apache and enable rewrite
		apachefile=/etc/httpd/conf.d/$name.conf

		echo "##  Creating the new virtual host in Apache.";
		echo >> $apachefile ""
		echo >> $apachefile ""
		echo >> $apachefile "LoadModule rewrite_module modules/mod_rewrite.so"
		echo >> $apachefile ""
		echo >> $apachefile "<VirtualHost *:80>"
		echo >> $apachefile "ServerAdmin webmaster@localhost"
		echo >> $apachefile "    <Directory $webdir/$name/public>"
		echo >> $apachefile "        Allow From All"
		echo >> $apachefile "        AllowOverride All"
		echo >> $apachefile "        Options +Indexes"
		echo >> $apachefile "   </Directory>"
		echo >> $apachefile "    DocumentRoot $webdir/$name/public"
		echo >> $apachefile "    ServerName $fqdn"
		echo >> $apachefile "        ErrorLog /var/log/httpd/snipeIT.error.log"
		echo >> $apachefile "        CustomLog /var/log/access.log combined"
		echo >> $apachefile "</VirtualHost>"

##TODO make sure this isnt already in there
		echo "##  Setting up hosts file.";
		echo >> $hosts "127.0.0.1 $hostname $fqdn"


		echo "##  Starting the apache server.";
		# Make apache start on boot and restart the daemon
		systemctl enable httpd.service
		systemctl restart httpd.service

		#Modify the Snipe-It files necessary for a production environment.
		echo "##  Modifying the Snipe-IT files necessary for a production environment."
		echo "	Setting up Timezone."
		tzone=$(timedatectl | gawk -F'[: ]+' ' $2 ~ /Timezone/ {print $3}');
		sed -i "s,UTC,$tzone,g" $webdir/$name/app/config/app.php

		echo "	Setting up bootstrap file."
		sed -i "s,www.yourserver.com,$hostname,g" $webdir/$name/bootstrap/start.php

		echo "	Setting up database file."
		cp $webdir/$name/app/config/production/database.example.php $webdir/$name/app/config/production/database.php
		sed -i "s,snipeit_laravel,snipeit,g" $webdir/$name/app/config/production/database.php
		sed -i "s,travis,snipeit,g" $webdir/$name/app/config/production/database.php
		sed -i "s,password'  => '',password'  => '$mysqluserpw',g" $webdir/$name/app/config/production/database.php

		echo "	Setting up app file."
		cp $webdir/$name/app/config/production/app.example.php $webdir/$name/app/config/production/app.php
		sed -i "s,production.yourserver.com,$fqdn,g" $webdir/$name/app/config/production/app.php
		sed -i "s,Change_this_key_or_snipe_will_get_ya,$random32,g" $webdir/$name/app/config/production/app.php
		sed -i "s,false,true,g" $webdir/$name/app/config/production/app.php

		echo "	Setting up mail file."
		cp $webdir/$name/app/config/production/mail.example.php $webdir/$name/app/config/production/mail.php

		# Change permissions on directories
		sudo chmod -R 755 $webdir/$name/app/storage
		sudo chmod -R 755 $webdir/$name/app/private_uploads
		sudo chmod -R 755 $webdir/$name/public/uploads
		sudo chown -R apache:apache $webdir/$name

		#Install / configure composer
		cd $webdir/$name

		curl -sS https://getcomposer.org/installer | php
		php composer.phar install --no-dev --prefer-source
		php artisan app:install --env=production

#TODO detect if SELinux and firewall are enabled to decide what to do
		#Add SELinux and firewall exception/rules. Youll have to allow 443 if you want ssl connectivity.
		# chcon -R -h -t httpd_sys_script_rw_t $webdir/$name/
		# firewall-cmd --zone=public --add-port=80/tcp --permanent
		# firewall-cmd --reload

		systemctl restart httpd.service
		;;
esac

echo ""
echo "  ***If you want mail capabilities, open $webdir/$name/app/config/production/mail.php and fill out the attributes***"
echo ""
echo "  ***Open http://$fqdn to login to Snipe-IT.***"
echo ""
echo ""
echo "##  Cleaning up..."
rm -f snipeit.sh
rm -f install.sh
rm -rf $tmp/
echo "##  Done!"
sleep 1
