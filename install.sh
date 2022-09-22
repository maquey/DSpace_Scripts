#! /bin/bash
export DSCONF="$PWD"/shost.conf
###################################################
cat > $DSCONF << "EOF"
# Automatically generated file; DO NOT EDIT / DO NOT DELETE.
DSPACE_PATH=/dspace
DSPACE_URL=https://github.com/DSpace/DSpace/releases/download/dspace-5.11/dspace-5.11-src-release.tar.gz
PSQL_SOU=/etc/postgresql/9.6/main
JAVA_TCNANA=/opt/tomcat/bin/setenv.sh
TCNANA_CON=/opt/tomcat/conf/server.xml
TCATA=/var/lib/tomcat9/conf/Catalina/localhost
REPO_MURL=localhost
EOF
###################################################

########################## Module A ##########################
PM_Prerequisites(){
	echo "deb http://apt.postgresql.org/pub/repos/apt/ jammy-pgdg main" >> /etc/apt/sources.list.d/pgdg.list
	curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null
	apt-get update
	apt-get install openjdk-8-jdk ant maven postgresql-9.6 dos2unix -y
	sed -i '$a JAVA_HOME="/usr/lib/jvm/java-1.8.0-openjdk-amd64/"' /etc/environment
	ufw default deny incoming
	ufw default allow outgoing
	ufw allow 22
	ufw allow 80
	ufw allow 443
	ufw allow 8080
	ufw enable      
}
PM_DSpace_A(){
	source $DSCONF
			curl -L $DSPACE_URL > dspace-source.tar.gz
			echo "Decompressing and transferring the package DSpace Source..."
			tar xf dspace-source.tar.gz --transform 's!^[^/]\+\($\|/\)!dspace-source\1!'
}
PM_DSpace_D_Inst(){
	###
	cd ./dspace-source
	mvn -U package
	cd ./dspace/target/dspace-installer
	ant fresh_install
	rm -rf "$HOME"/.m2/repository
	
}
PM_Postgres_A(){
	if psql  -lqtA | cut -d\| -f1 | grep -qFx "dspace"; then
		echo "The database already exists"
	else
		createuser --username=postgres --no-superuser dspace
		createdb --username=postgres --owner=dspace --encoding=UNICODE dspace
		psql --username=postgres dspace -c "CREATE EXTENSION pgcrypto;"
	fi 
}
PM_Postgres_B(){
	source $DSCONF
	while true
	do
	read -p "$(echo -e 'Enter password for new role: \n\b')"  Dream 
	read -p "$(echo -e 'Enter it again: \n\b')"  Land
	if [ "$Dream" = "$Land" ]
	then
		sudo -u postgres psql -c "ALTER USER dspace WITH PASSWORD '${Dream}';"
		sed -i "s|db.password = dspace|db.password = ${Dream}|g" $PWD/dspace-source/dspace/config/dspace.cfg
		break
	else
		echo -e "Passwords didn't match. \n"
	fi
	done
	###
	unset Dream && unset Land
}
PM_Postgres_C(){
	source $DSCONF
	if [ -d "$PSQL_SOU" ]
	then
		if grep -xq "host dspace dspace 127.0.0.1 255.255.255.255 md5" $PSQL_SOU/pg_hba.conf ; then
		  echo "pg_hba.conf - Ok..."
		else
		  echo "Setting the pg_hba.conf..."
		  sed -i '$a host dspace dspace 127.0.0.1 255.255.255.255 md5' $PSQL_SOU/pg_hba.conf
		  /etc/init.d/postgresql restart
		fi 
		###
		if grep -xq "# Adapting DSpace for postgresql" $PSQL_SOU/postgresql.conf ; then
		  echo "postgresql.conf - Ok..."
		else
		  echo "Setting the postgresql.conf..."
		  sed -i "s|#listen_addresses = 'localhost'|listen_addresses = 'localhost'|g" $PSQL_SOU/postgresql.conf
		  sed -i '$a # Adapting DSpace for postgresql' $PSQL_SOU/postgresql.conf
		  /etc/init.d/postgresql restart
		fi 	
	else
		echo "You need to install postgresql 9.6"
	fi
}

########################## Module B ##########################
PM_Tomcat(){
	source $DSCONF
	wget -4 https://archive.apache.org/dist/tomcat/tomcat-8/v8.5.78/bin/apache-tomcat-8.5.78.tar.gz
	tar xvzf apache-tomcat-8.5.78.tar.gz
	mv apache-tomcat-8.5.78 /opt/tomcat
	rm apache-tomcat-8.5.78.tar.gz
	####Java Memory Settings####
	ram=$(awk '/^(MemTotal)/{print $2}' /proc/meminfo)
	lim=12582912
	if [ "$ram" -ge "$lim" ]; then
	echo 'JAVA_OPTS="-Djava.awt.headless=true -Xmx2048m -Xms1024m -XX:MaxPermSize=1024m -XX:+UseConcMarkSweepGC -XX:+CMSIncrementalMode -Dfile.encoding=UTF-8"' > $JAVA_TCNANA
	else
	echo 'JAVA_OPTS="-Djava.awt.headless=true -Xmx1024m -Xms512m -XX:MaxPermSize=512m -XX:+UseConcMarkSweepGC -XX:+CMSIncrementalMode -Dfile.encoding=UTF-8"' > $JAVA_TCNANA
	fi
	###Tomcat service###
cat > /etc/init.d/tomcat <<"TXT"
#!/bin/bash
### BEGIN INIT INFO
# Provides:        tomcat8
# Required-Start:  $network
# Required-Stop:   $network
# Default-Start:   2 3 4 5
# Default-Stop:    0 1 6
# Short-Description: Start/Stop Tomcat server
### END INIT INFO

PATH=/sbin:/bin:/usr/sbin:/usr/bin

start() {
 sh /opt/tomcat/bin/startup.sh
}

stop() {
 sh /opt/tomcat/bin/shutdown.sh
}

case $1 in
  start|stop) $1;;
  restart) stop; start;;
  *) echo "Run as $0 <start|stop|restart>"; exit 1;;
esac
TXT
chmod +x /etc/init.d/tomcat
update-rc.d tomcat defaults
}
########################## Exports #########################
#A
export -f PM_Prerequisites
export -f PM_DSpace_A
export -f PM_DSpace_D_Inst
export -f PM_Postgres_A
export -f PM_Postgres_B
export -f PM_Postgres_C
#B
export -f PM_Tomcat
############################################################################################
		if getent passwd | grep -c '^dspace:' > /dev/null 2>&1; then
				PM_Prerequisites
				mkdir /dspace
				chown dspace /dspace
				#Module A
				PM_DSpace_A
				su postgres -c "bash -c PM_Postgres_A"
				PM_Postgres_B && PM_Postgres_C
				PM_DSpace_D_Inst
				#Module B
				PM_Tomcat
				cp -r /dspace/webapps/* /opt/tomcat/webapps
				service tomcat start
			else
				PM_Prerequisites
				mkdir /dspace
				echo "Creating the user...."
				useradd -m dspace
				chown dspace /dspace
				#Module A
				PM_DSpace_A
				su postgres -c "bash -c PM_Postgres_A"
				PM_DSpace_D_Inst
				#Module B
				PM_Tomcat
				cp -r /dspace/webapps/* /opt/tomcat/webapps
				service tomcat start
			fi
