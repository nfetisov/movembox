#!/bin/bash

echo "Transferencia entre buzones. v.0.1"
echo "RUN AS ZIMBRA USER!"

echo -n "Ingrese la cuenta (correo electrónico) que desea mover: "; read ACCOUNT1
zimbraMailHost=`zmprov -l ga $ACCOUNT1 | grep zimbraMailHost`
test=${zimbraMailHost:0:14}
if [ "$test" != "zimbraMailHost" ]; then
echo "Účet $ACCOUNT1 neexistuje!"
exit 255;
fi

SERVER1=${zimbraMailHost:16}
echo "Servidor de origen (ubicación actual): $SERVER1"

echo -n "Por favor, introduzca un servidor destino: "; read SERVER2
if [ $SERVER1 == $SERVER2 ]; then
echo "¡Los servidores de origen y destino no pueden ser el mismo!"
exit 255;
fi

echo -n "Ingrese un directorio temporal para la ubicación de datos: "; read TEMPDIR
if [ ! -d $TEMPDIR ]; then
echo "¡El directorio $TEMPDIR no existe!"
exit 255;
fi

# creando una nueva cuenta
echo "Se está creando una cuenta temporal en el servidor $SERVER2..."
TEMPACCOUNT="temp_$ACCOUNT1"

# contraseña y otras cosas
echo "Copiando la configuración de la cuenta anterior..."

NAMA_FILE="$TEMPDIR/zcs-acc-add.zmp"
LDIF_FILE="$TEMPDIR/zcs-acc-mod.ldif"

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
    echo "¡No se pueden mover las cuentas del sistema!"
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
    if [ -f $LDIF_FILE ];
        then
            zmprov < $NAMA_FILE
            ldapmodify -f $LDIF_FILE -x -H $LDAP_MASTER_URL -D cn=config -w $ZIMBRA_LDAP_PASSWORD
        else
            echo "Chyba, soubor $LDIF_FILE neexistuje."
            exit 255
        fi
else
    echo "Error, el archivo $NAMA_FILE no existe."
    exit 255
fi

echo "Cuenta temporal creada."

echo "Iniciando la transferencia de datos."

echo "Copia de seguridad de $ACCOUNT1 anterior en el servidor $SERVER1"
ZMBOX=/opt/zimbra/bin/zmmailbox
DATE=`date +"%Y%m%d%H%M%S"`
$ZMBOX -z -m $ACCOUNT getRestURL "//?fmt=tgz" > $TEMPDIR/$ACCOUNT1.$DATE.tar.gz

echo "Restaurar datos a la cuenta temporal $TEMPACCOUNT del servidor $SERVER2"
$ZMBOX -z -m $TEMPACCOUNT postRestURL "//?fmt=tgz&resolve=reset" $TEMPDIR/$ACCOUNT1.$DATE.tar.gz

echo "Cambiar el nombre de la cuenta anterior a old_$ACCOUNT1..."
# renombrar el viejo
zmprov renameAccount $ACCOUNT1 old_$ACCOUNT1

echo "Cerrar cuenta antigua old_$ACCOUNT1..."
zmprov ma old_$ACCOUNT1  zimbraAccountStatus closed

echo "Renombrar cuenta antigua old_ $ACCOUNT1 ..."
# renombrar nuevo
zmprov renameAccount $TEMPACCOUNT $ACCOUNT1

echo "HECHO."
exit
