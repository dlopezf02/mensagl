#!/bin/bash
set -e
export DUCKDNS_SUBDOMAIN="${DUCKDNS_SUBDOMAIN}"
export DB_USERNAME="${DB_USERNAME}"
export DB_PASSWORD="${DB_PASSWORD}"

sudo apt update -y

sudo apt install prosody -y
sudo apt install lua-dbi-mysql lua-dbi-postgresql lua-dbi-sqlite3 -y
sudo rm -rf /etc/prosody/prosody.cfg.lua

echo "
plugin_paths = { '/usr/src/prosody-modules' } -- non-standard plugin path so we can keep them up to date with mercurial
modules_enabled = {
                'roster'; -- Allow users to have a roster. Recommended ;)
                'saslauth'; -- Authentication for clients and servers. Recommended if you want to log in.
                'tls'; -- Add support for secure TLS on c2s/s2s connections
                'dialback'; -- s2s dialback support
                'disco'; -- Service discovery
                'private'; -- Private XML storage (for room bookmarks, etc.)
                'vcard4'; -- User Profiles (stored in PEP)
                'vcard_legacy'; -- Conversion between legacy vCard and PEP Avatar, vcard
                'version'; -- Replies to server version requests
                'uptime'; -- Report how long server has been running
                'time'; -- Let others know the time here on this server
                'ping'; -- Replies to XMPP pings with pongs
                'register'; --Allows clients to register an account on your server
                'pep'; -- Enables users to publish their mood, activity, playing music and more
                'carbons'; -- XEP-0280: Message Carbons, synchronize messages accross devices
                'smacks'; -- XEP-0198: Stream Management, keep chatting even when the network drops for a few seconds
                'mam'; -- XEP-0313: Message Archive Management, allows to retrieve chat history from server
                'csi_simple'; -- XEP-0352: Client State Indication
                'admin_adhoc'; -- Allows administration via an XMPP client that supports ad-hoc commands
                'blocklist'; -- XEP-0191  blocking of users
                'bookmarks'; -- Synchronize currently joined groupchat between different clients.
                'server_contact_info'; --add contact info in the case of issues with the server
                --'cloud_notify'; -- Support for XEP-0357 Push Notifications for compatibility with ChatSecure/iOS.
                -- iOS typically end the connection when an app runs in the background and requires use of Apple's Push servers to wake up and receive a message. Enabling this module allows your server to do that for your contacts on iOS.
                -- However we leave it commented out as it is another example of vertically integrated cloud platforms at odds with federation, with all the meta-data-based surveillance consequences that that might have.
                'bosh';
                'websocket';
                's2s_bidi';
                's2s_whitelist';
                's2sout_override';
                'certs_s2soutinjection';
                's2s_auth_certs';
                's2s_auth_dane_in';
                's2s';
                'scansion_record';
                'server_contact_info';
};
allow_registration = false; -- Enable to allow people to register accounts on your server from their clients, for more information see http://prosody.im/doc/creating_accounts
certificates = '/etc/prosody/certs' -- Path where prosody looks for the certificates see: https://prosody.im/doc/letsencrypt
--https_certificate = 'certs/lobby.${DUCKDNS_SUBDOMAIN}.duckdns.org.crt'
c2s_require_encryption = true -- Force clients to use encrypted connections
s2s_secure_auth = true
s2s_secure_domains = { 'openfire-equipo45.duckdns.org' };
pidfile = '/var/run/prosody/prosody.pid'
authentication = 'internal_hashed'
archive_expires_after = '1w' -- Remove archived messages after 1 week
log = { --disable for extra privacy
        info = '/var/log/prosody/prosody.log'; -- Change 'info' to 'debug' for verbose logging
        error = '/var/log/prosody/prosody.err';
        '*syslog';
}
    disco_items = { -- allows clients to find the capabilities of your server
        {'upload.${DUCKDNS_SUBDOMAIN}.duckdns.org', 'file uploads'};
        {'lobby.${DUCKDNS_SUBDOMAIN}.duckdns.org', 'group chats'};
}
admin = { 'mario@${DUCKDNS_SUBDOMAIN}.duckdns.org' };
VirtualHost '${DUCKDNS_SUBDOMAIN}.duckdns.org'

storage = 'sql'
sql = { driver = 'MySQL', database = 'xmpp_db', username = '${DB_USERNAME}', password = '${DB_PASSWORD}', host = '10.216.3.10' }

ssl = {
    certificate = 'certs/${DUCKDNS_SUBDOMAIN}.duckdns.org.crt',
    key = 'certs/${DUCKDNS_SUBDOMAIN}.duckdns.org.key',
}
Component 'upload.${DUCKDNS_SUBDOMAIN}.duckdns.org' 'http_upload'
ssl = {
    certificate = '/etc/prosody/certs/lobby.${DUCKDNS_SUBDOMAIN}.duckdns.org.crt',
    key = '/etc/prosody/certs/lobby.${DUCKDNS_SUBDOMAIN}.duckdns.org.key',
}
Component 'lobby.${DUCKDNS_SUBDOMAIN}.duckdns.org' 'muc'
ssl = {
    certificate = '/etc/prosody/certs/lobby.${DUCKDNS_SUBDOMAIN}.duckdns.org.crt',
    key = '/etc/prosody/certs/lobby.${DUCKDNS_SUBDOMAIN}.duckdns.org.key',
}
modules_enabled = { 'muc_mam', 'vcard_muc' } -- enable archives and avatars for group chats
restrict_room_creation = 'admin'
default_config = {persistent = false;}
Component 'proxy.${DUCKDNS_SUBDOMAIN}.duckdns.org' 'proxy65'
ssl = {
    certificate = '/etc/prosody/certs/lobby.${DUCKDNS_SUBDOMAIN}.duckdns.org.crt',
    key = '/etc/prosody/certs/lobby.${DUCKDNS_SUBDOMAIN}.duckdns.org.key',
}
" | sudo tee -a /etc/prosody/prosody.cfg.lua > /dev/null 

sudo apt install mysql-client mysql-server -y
sleep 360
sudo mysql -h "10.216.3.10" -u "${DB_USERNAME}" -p"${DB_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS xmpp_db;"

sudo systemctl restart prosody
sudo prosodyctl register mario ${DUCKDNS_SUBDOMAIN}.duckdns.org Admin123
sudo prosodyctl register carlos ${DUCKDNS_SUBDOMAIN}.duckdns.org Admin123
sudo prosodyctl register dieguin ${DUCKDNS_SUBDOMAIN}.duckdns.org Admin123
sudo prosodyctl register martin ${DUCKDNS_SUBDOMAIN}.duckdns.org Admin123
