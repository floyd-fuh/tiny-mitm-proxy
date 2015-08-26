#You want to iptable redirect your clients to this port:
IN_PORT=9201
#That means you want something like:
#iptables -t nat -A PREROUTING -i $fakeAP_interface -p tcp --dport 443 -j DNAT --to $SSL_PROXY_IP:9201
#iptables -t nat -A PREROUTING -i $fakeAP_interface -p tcp --dport 443 -j REDIRECT --to-port 9201
#Where you want to redirect the incoming traffic to:
OUT_PORT=443
SERVERNAME=example.com
#We redirect through localhost, so you can sniff on lo with Wireshark as well with filter tcp.port==59997
#It's simply important that this port is not occupied
AVAILABLE_PORT_ON_LOCALHOST=59997
#The files where the traffic is written to
CLIENT_OUTGOING_FILE=incoming_client_traffic_raw_$IN_PORT.bin
SERVER_INCOMING_FILE=incoming_server_traffic_raw_$IN_PORT.bin

#Attention, this is fine on a standard Kali, but you might not want to killall on every system...
killall openssl 2>/dev/null
killall nc 2>/dev/null
rm $CLIENT_OUTGOING_FILE 2>/dev/null
rm $SERVER_INCOMING_FILE 2>/dev/null
sleep 1 #Waiting until ports are freed by OS...

if [ -e cakey.pem ]; then
	echo "+++Seems like we already have certs etc., not generating but using the ones in current directory"
else
	#Make keys etc.
	#sudo apt-get install openssl
	#CA
	openssl genrsa -aes256 -out cakey.pem 2048
	echo "+++Details for CA CERTIFICATE:"
	openssl req -new -x509 -days 3650 -key cakey.pem -out ca-cert.pem -set_serial 1
	touch index.txt
	echo "01" > serial
	#Server
	#add -nodes if no password should be used for server certificate
	echo "+++Details for SERVER CERTIFICATE:"
	openssl req -new -newkey rsa:1024 -nodes -out servercsr.pem -keyout serverkey.pem -days 3650
	#sign server csr with CA
	openssl x509 -req -in servercsr.pem -out servercert.pem -CA ca-cert.pem -CAkey cakey.pem -CAserial ./serial -days 3650
	rm servercsr.pem
	#Client
	#openssl req -new -newkey rsa:1024 -nodes -out client_csr.pem -keyout client_key.pem -days 3650
	#openssl x509 -req -in client_csr.pem -out client_cert.pem -CA ca-cert.pem -CAkey vpn-cakey.pem -CAserial ./serial -days 3650
	#rm client_csr.pem
	#Diffie-Hellman parameter
	openssl dhparam -out dh1024.pem 1024
	echo "+++You want to install ca-cert.pem on your client"
fi

echo "+++Listening on $IN_PORT, redirecting to $SERVERNAME:$OUT_PORT"
nc -l -p $AVAILABLE_PORT_ON_LOCALHOST | tee $CLIENT_OUTGOING_FILE | openssl s_client -quiet -connect $SERVERNAME:$OUT_PORT > $SERVER_INCOMING_FILE &
sleep 1
tail -f $SERVER_INCOMING_FILE | openssl s_server -quiet -accept $IN_PORT -cert servercert.pem -key serverkey.pem -dhparam dh1024.pem | nc 127.0.0.1 $AVAILABLE_PORT_ON_LOCALHOST


