# block_unsubscribe
Automatic email unsubscribe script

This script scan your imap server DIR, and for each **unread** message try to self unsubscribe, or open an external browser if it failed and you wants (ext_limit)

##Usage :

./unsubscribe2.pl --user user --server server [--password password] [--port 993] [--nossl] [--uid] [--ext_limit 10] [--dir INBOX]

example :
./unsubscribe2.pl  --user imapusermane --server imap.free.fr --ext_limit=20 --dir PUB


where, 

--user is your imap user name

--server is the imap server name

optional 

--dir folder to search for unread mail

--ext_limit=xx xx the maximum number of complex unsubscribe web page to open in your browser (set to 0 do disable)

--password  : password

--port 993 : server port number

--nossl

--uid
