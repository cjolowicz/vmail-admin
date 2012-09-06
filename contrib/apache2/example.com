<IfModule mod_dbd.c>
<IfModule mod_authn_dbd.c>
<VirtualHost *:443>
    ServerName example.com

    DBDriver mysql
    DBDParams "dbname=mail host=127.0.0.1 user=mail pass=xxxxxx"

    <Location />
	AuthType Basic
	AuthName "Restricted Area"
	AuthBasicProvider dbd
	Require valid-user
	AuthDBDUserPWQuery \
	    "SELECT CONCAT('{SHA}', password) FROM users WHERE user = CONCAT(%s, '@example.com');"
	AuthDBDUserRealmQuery \
	    "SELECT CONCAT('{SHA}', password) FROM users WHERE user = CONCAT(%s, CONCAT('@', %s));"
    </Location>
</VirtualHost>
</IfModule>
</IfModule>
