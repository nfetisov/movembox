#!/bin/bash

echo "Transfer mailboxes between mailstores. v.0.1"
echo "RUN AS ZIMBRA USER!"

echo -n "Enter the account (email) you want to move:"; read ACCOUNT1
zimbraMailHost=`zmprov -l ga $ACCOUNT1 | grep zimbraMailHost`
test=${zimbraMailHost:0:14}
if [ "$test" != "zimbraMailHost" ]; then
echo "Account ${ACCOUNT1} does not exist!"
exit 255;
fi

SERVER1=${zimbraMailHost:16}
echo "Origin server (current location): $SERVER1"

echo -n "Please enter a destination server:"; read SERVER2
if [ "${SERVER1}" == "${SERVER2:?}" ]; then
echo "The source and destination servers cannot be the same!"
exit 255;
fi

echo -n "Enter a temporary directory for the data location: "; read TEMPDIR
if [ ! -d "${TEMPDIR}" ]; then
echo "The ${TEMPDIR} directory does not exist!"
exit 255;
fi

# creating a new account
echo "A temporary account is being created on the server ${SERVER2}..."
TEMPACCOUNT="temp_${ACCOUNT1}"

# password and other things
echo "Copying the previous account settings..."

NAMA_FILE="${TEMPDIR}/zcs-acc-add.zmp"
LDIF_FILE="${TEMPDIR}/zcs-acc-mod.ldif"

rm -f $NAMA_FILE
rm -f $LDIF_FILE

touch $NAMA_FILE
touch $LDIF_FILE

NAME=`echo $ACCOUNT1`;
DOMAIN=`echo $ACCOUNT1 | awk -F@ '{print $2}'`;
ACCOUNT=`echo $ACCOUNT1 | awk -F@ '{print $1}'`;
ACC=`echo $ACCOUNT1 | cut -d '.' -f1`

ZIMBRA_LDAP_PASSWORD=`zmlocalconfig -s zimbra_ldap_password | cut -d ' ' -f3`
LDAP_MASTER_URL="ldapi:///"

OBJECT="(&(objectClass=zimbraAccount)(mail=$NAME))"
dn=`/opt/zimbra/common/bin/ldapsearch -H $LDAP_MASTER_URL -w $ZIMBRA_LDAP_PASSWORD -D uid=zimbra,cn=admins,cn=zimbra -x $OBJECT | grep dn:`
displayName=`/opt/zimbra/common/bin/ldapsearch -H $LDAP_MASTER_URL -w $ZIMBRA_LDAP_PASSWORD -D uid=zimbra,cn=admins,cn=zimbra -x $OBJECT | grep displayName: | cut -d ':' -f2 | sed 's/^ *//g' | sed 's/ *$//g'`
givenName=`/opt/zimbra/common/bin/ldapsearch -H $LDAP_MASTER_URL -w $ZIMBRA_LDAP_PASSWORD -D uid=zimbra,cn=admins,cn=zimbra -x $OBJECT | grep givenName: | cut -d ':' -f2 | sed 's/^ *//g' | sed 's/ *$//g'`
#userPassword=`/opt/zimbra/common/bin/ldapsearch -H $LDAP_MASTER_URL -w $ZIMBRA_LDAP_PASSWORD -D uid=zimbra,cn=admins,cn=zimbra -x $OBJECT | grep userPassword: | cut -d ':' -f3 | sed 's/^ *//g' | sed 's/ *$//g'`
userPassword=`zmprov -l ga $ACCOUNT1 userPassword | grep userPassword | sed 's/userPassword: //'`
cn=`/opt/zimbra/common/bin/ldapsearch -H $LDAP_MASTER_URL -w $ZIMBRA_LDAP_PASSWORD -D uid=zimbra,cn=admins,cn=zimbra -x $OBJECT | grep cn: | cut -d ':' -f2 | sed 's/^ *//g' | sed 's/ *$//g'`
initials=`/opt/zimbra/common/bin/ldapsearch -H $LDAP_MASTER_URL -w $ZIMBRA_LDAP_PASSWORD -D uid=zimbra,cn=admins,cn=zimbra -x $OBJECT | grep initials: | cut -d ':' -f2 | sed 's/^ *//g' | sed 's/ *$//g'`
sn=`/opt/zimbra/common/bin/ldapsearch -H $LDAP_MASTER_URL -w $ZIMBRA_LDAP_PASSWORD -D uid=zimbra,cn=admins,cn=zimbra -x $OBJECT | grep sn: | cut -d ':' -f2 | sed 's/^ *//g' | sed 's/ *$//g'`


if [ $ACC = "admin" ] || [ $ACC = "wiki" ] || [ $ACC = "galsync" ] || [ $ACC = "ham" ] || [ $ACC = "spam" ]; then
    echo "System accounts cannot be moved!"
    exit 255
else
    echo "createAccount $TEMPACCOUNT XXXccc123wQ displayName '$displayName' givenName '$givenName' sn '$sn' initials '$initials' zimbraPasswordMustChange FALSE zimbraMailHost $SERVER2" >> $NAMA_FILE

    pos2=`expr index "$TEMPACCOUNT" @`
    TEMPUSER=${TEMPACCOUNT:0:pos2-1}
    dn2="${dn/$ACCOUNT/$TEMPUSER}"
    echo "$dn2
changetype: modify
replace: userPassword
userPassword: $userPassword
" >> $LDIF_FILE
    echo "Adding account $NAME"
fi


if [ -f $NAMA_FILE ];
then
    if [ -f "${LDIF_FILE}" ];
        then
            zmprov < $NAMA_FILE
            ldapmodify -f $LDIF_FILE -x -H $LDAP_MASTER_URL -D cn=config -w $ZIMBRA_LDAP_PASSWORD
        else
            echo "Error, the ${LDIF_FILE} file does not exist."
            exit 255
        fi
else
    echo "Error, the $NAMA_FILE file does not exist."
    exit 255
fi

echo "Temporary account created."

echo "Starting the data transfer."

echo "Backup of previous ${ACCOUNT1} on server ${SERVER1}"
ZMBOX=/opt/zimbra/bin/zmmailbox
DATE=`date +"%Y%m%d%H%M%S"`
$ZMBOX -z -m $ACCOUNT getRestURL "//?fmt=tgz" > "${TEMPDIR}/{$ACCOUNT1}.${DATE}.tar.gz"

echo "Restore data to the temporary account ${TEMPACCOUNT} on the server ${SERVER2}"
$ZMBOX -z -m $TEMPACCOUNT postRestURL "//?fmt=tgz&resolve=reset" "${TEMPDIR}/${ACCOUNT1}.${DATE}.tar.gz"

echo "Rename the old account to old_${ACCOUNT1}..."
# rename the old
zmprov renameAccount "${ACCOUNT1}" "old_${ACCOUNT1}"

echo "Close old account old_${ACCOUNT1}..."
zmprov ma "old_${ACCOUNT1}"  zimbraAccountStatus closed

echo "Rename temporary account to ${ACCOUNT1} ..."
# rename new
zmprov renameAccount "${TEMPACCOUNT}" "${ACCOUNT1}"

echo "DONE."
exit
