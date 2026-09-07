#!/usr/bin/env bash
set -Eeuo pipefail
BASE=/etc/hyto-ssh; ACC=$BASE/accounts; BIN=/usr/local/bin/hyto; XR=/usr/local/etc/xray
TG=$BASE/telegram.conf; WA=$BASE/whatsapp.conf
LICENSE_FILE="$BASE/license.key"
WORKER_URL="https://hyto-license.hyto0250.workers.dev"

root(){ [ "$EUID" = 0 ] || { echo 'Lance avec sudo/root.'; exit 1; }; }

verify_license(){
    local key=""
    if [ -f "$LICENSE_FILE" ]; then
        key=$(cat "$LICENSE_FILE")
    fi

    while true; do
        if [ -z "$key" ]; then
            clear
            echo '╔══════════════════════════════════════╗'
            echo '║          VERIFICATION LICENCE        ║'
            echo '╚══════════════════════════════════════╝'
            read -r -p "Entrez votre clé de licence : " key
            [ -z "$key" ] && continue
        fi

        echo "[*] Vérification de la licence..."
        RESPONSE=$(curl -s "${WORKER_URL}?key=${key}")

        VALID=$(echo "$RESPONSE" | grep -o '"valid":[^,}]*' | cut -d ':' -f2 | tr -d '[:space:]')
        MESSAGE=$(echo "$RESPONSE" | grep -o '"message":"[^"]*"' | cut -d '"' -f4)

        if [ "$VALID" = "true" ]; then
            USER_NAME=$(echo "$RESPONSE" | grep -o '"user":"[^"]*"' | cut -d '"' -f4)
            echo "[+] Licence valide ! Bienvenue, ${USER_NAME:-Client}."
            echo "$key" > "$LICENSE_FILE"
            sleep 1
            break
        else
            echo "[-] Accès refusé : ${MESSAGE:-Clé invalide ou expirée.}"
            rm -f "$LICENSE_FILE"
            key=""
            read -r -p "Appuyez sur Entrée pour réessayer..." _
        fi
    done
}

pause(){ read -r -p $'\nEntrée pour continuer...' _; }
ip(){ curl -4fsS https://api.ipify.org 2>/dev/null || hostname -I|awk '{print $1}'; }
setup(){
 root; verify_license; apt-get update -y; apt-get install -y curl wget jq uuid-runtime openssl ca-certificates unzip git python3 dnsutils lsof openssh-server
 mkdir -p "$ACC" "$XR"; touch "$BASE/accounts.db"; chmod 700 "$BASE"; cp -f "$0" "$BIN"; chmod 755 "$BIN"
 cat >/etc/profile.d/hyto.sh <<'MOTD'
printf '\n\033[1;36m╔══════════════════════════════════════╗\033[0m\n\033[1;36m║          HYTO SSH — SERVER          ║\033[0m\n\033[1;36m╚══════════════════════════════════════╝\033[0m\nIP : %s\n\n\033[1;33mSCRIPT BY HYTO\033[0m\nWhatsApp : 659550700\nTelegram : https://t.me/free_seuf_illimite_tout_pays\n\n' "$(curl -4fsS https://api.ipify.org 2>/dev/null || hostname -I|awk '{print $1}')"
MOTD
 systemctl enable --now ssh; echo 'HYTO SSH installé. Tape: hyto'; }
ssh_menu(){ while :; do clear; echo '--- SSH ---'; echo '1) Créer'; echo '2) Supprimer'; echo '3) Lister'; echo '4) Redémarrer SSH'; echo '0) Retour'; read -r -p 'Choix: ' c; case $c in
1) read -r -p 'Nom (0=Retour): ' u; [ "$u" = 0 ]&&continue; read -r -s -p 'Mot de passe: ' p; echo; read -r -p 'Jours (0=annuler): ' d; [ "$d" = 0 ]&&continue; useradd -m -s /bin/bash -e "$(date -d "+$d days" +%F)" "$u"; echo "$u:$p"|chpasswd; echo "Créé: $u"; pause;;
2) read -r -p 'Nom (0=Retour): ' u; [ "$u" = 0 ]&&continue; userdel -r "$u" 2>/dev/null||true; pause;;
3) awk -F: '$3>=1000&&$1!="nobody"{print $1}' /etc/passwd; pause;;
4) systemctl restart ssh; pause;;0)return;;esac; done; }
xray_install(){
 [ -x /usr/local/bin/xray ]&&return
 local v=v26.7.28 a; a=$(dpkg --print-architecture); case "$a" in amd64)a=x86_64;;arm64)a=arm64-v8a;;*) echo 'Architecture non supportée'; return 1;;esac
 wget -q "https://github.com/XTLS/Xray-core/releases/download/$v/Xray-linux-$a.zip" -O /tmp/xray.zip; unzip -oq /tmp/xray.zip -d "$XR"; chmod 755 "$XR/xray"; ln -sf "$XR/xray" /usr/local/bin/xray
 cat >/etc/systemd/system/xray.service <<'UNIT'
[Unit]
Description=Xray
After=network.target
[Service]
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
 cat >"$XR/config.json" <<'JSON'
{"log":{"loglevel":"warning"},"inbounds":[],"outbounds":[{"protocol":"freedom","tag":"direct"}]}
JSON
 systemctl daemon-reload; systemctl enable xray; }
xray_add(){
 xray_install; local pr n id port; read -r -p 'Protocole vless/vmess/trojan (0=Retour): ' pr; [ "$pr" = 0 ]&&return; [[ "$pr" =~ ^(vless|vmess|trojan)$ ]]||return; read -r -p 'Nom (0=Retour): ' n; [ "$n" = 0 ]&&return; read -r -p 'Jours (0=annuler): ' d; [ "$d" = 0 ]&&return; id=$(uuidgen); case "$pr" in vless)port=443;;vmess)port=8443;;trojan)port=2053;;esac
 python3 - "$XR/config.json" "$pr" "$n" "$id" "$port" <<'PY'
import json,sys
f,pr,name,uid,port=sys.argv[1:]; port=int(port); c=json.load(open(f)); i=next((x for x in c['inbounds'] if x['port']==port),None)
if i is None:
 s={'clients':[]};
 if pr=='vless': s['decryption']='none'
 i={'listen':'0.0.0.0','port':port,'protocol':pr,'settings':s,'tag':pr}; c['inbounds'].append(i)
i['settings']['clients'].append({'password':uid,'email':name} if pr=='trojan' else {'id':uid,'email':name})
json.dump(c,open(f,'w'),indent=2)
PY
 xray -test -config "$XR/config.json"; systemctl restart xray
 printf 'HYTO SSH\nWhatsApp: 659550700\nTelegram: https://t.me/free_seuf_illimite_tout_pays\n\nProtocol: %s\nServer: %s\nPort: %s\nUser: %s\nID/Password: %s\n' "$pr" "$(ip)" "$port" "$n" "$id" >"$ACC/${pr}_${n}.txt"; echo "Fichier: $ACC/${pr}_${n}.txt"; pause; }
xray_menu(){ while :; do clear; echo '--- XRAY ---'; echo '1) Installer'; echo '2) Créer VLESS/VMess/Trojan'; echo '3) Tester'; echo '4) Redémarrer'; echo '5) Logs'; echo '0) Retour'; read -r -p 'Choix: ' c; case $c in 1)xray_install;pause;;2)xray_add;;3)xray -test -config "$XR/config.json";pause;;4)systemctl restart xray;pause;;5)journalctl -u xray --no-pager -n 50;pause;;0)return;;esac; done; }
zivpn_menu(){ while :; do clear; echo '--- ZIVPN UDP ---'; echo '1) Installer'; echo '2) Ajouter'; echo '3) Supprimer'; echo '4) Lister'; echo '5) Backup'; echo '6) Restore'; echo '7) Désinstaller'; echo '0) Retour'; read -r -p 'Choix: ' c; case $c in 1)bash <(curl -fsSL https://raw.githubusercontent.com/potatonc/zivpn-udp/main/zi.sh) install;pause;;2)bash <(curl -fsSL https://raw.githubusercontent.com/potatonc/zivpn-udp/main/zi.sh) add;pause;;3)bash <(curl -fsSL https://raw.githubusercontent.com/potatonc/zivpn-udp/main/zi.sh) del;pause;;4)bash <(curl -fsSL https://raw.githubusercontent.com/potatonc/zivpn-udp/main/zi.sh) list;pause;;5)bash <(curl -fsSL https://raw.githubusercontent.com/potatonc/zivpn-udp/main/zi.sh) backup;pause;;6)bash <(curl -fsSL https://raw.githubusercontent.com/potatonc/zivpn-udp/main/zi.sh) restore;pause;;7)bash <(curl -fsSL https://raw.githubusercontent.com/potatonc/zivpn-udp/main/zi.sh) uninstall;pause;;0)return;;esac;done; }
udp_menu(){ while :; do clear; echo '--- UDP CUSTOM ---'; echo '1) Installer'; echo '2) Configuration'; echo '3) Redémarrer'; echo '4) Logs'; echo '0) Retour'; read -r -p 'Choix: ' c; case $c in 1)rm -rf /tmp/udp-custom;git clone -q https://github.com/http-custom/udp-custom /tmp/udp-custom;cd /tmp/udp-custom;chmod +x install.sh;./install.sh;pause;;2)cat /root/udp/config.json 2>/dev/null||echo Non-installé;pause;;3)systemctl restart udp-custom 2>/dev/null||true;systemctl restart udpgw 2>/dev/null||true;pause;;4)journalctl -u udp-custom -u udpgw --no-pager -n 50;pause;;0)return;;esac;done; }
slow_menu(){ while :; do clear; echo '--- SLOWDNS / IODINE ---'; echo '1) Installer'; echo '2) Configurer serveur'; echo '3) État'; echo '4) Logs'; echo '0) Retour'; read -r -p 'Choix: ' c; case $c in 1)apt-get install -y iodine;pause;;2)read -r -p 'NS/subdomain (0=Retour): ' host;[ "$host" = 0 ]&&continue;read -r -s -p 'Mot de passe: ' pass;echo;read -r -p 'IP tunnel [10.0.1.1]: ' tip;tip=${tip:-10.0.1.1};printf 'START_IODINED=true\nIODINED_ARGS="-c %s %s"\nIODINED_PASSWORD="%s"\n' "$tip" "$host" "$pass" >/etc/default/iodine;sysctl -w net.ipv4.ip_forward=1 >/dev/null;systemctl enable --now iodined 2>/dev/null||true;echo 'A + NS DNS requis.';pause;;3)systemctl status iodined --no-pager;pause;;4)journalctl -u iodined --no-pager -n 50;pause;;0)return;;esac;done; }
tg_menu(){ while :; do clear; echo '--- TELEGRAM BOT ---'; echo '1) Configurer token + Admin ID'; echo '2) Tester API'; echo '3) Installer service'; echo '4) Logs'; echo '0) Retour'; read -r -p 'Choix: ' c; case $c in 1)read -r -p 'Token (0=Retour): ' t;[ "$t" = 0 ]&&continue;read -r -p 'Admin ID: ' a;printf 'TOKEN=%q\nADMIN_ID=%q\n' "$t" "$a">$TG;chmod 600 $TG;pause;;2)source "$TG" 2>/dev/null;curl -fsS "https://api.telegram.org/bot$TOKEN/getMe"|jq .;pause;;3)cat >$BASE/tg-bot.py <<'PY'
import json,urllib.request,time,subprocess
c={}
for l in open('/etc/hyto-ssh/telegram.conf'): k,v=l.strip().split('=',1);c[k]=v.strip("'\"")
t=c['TOKEN'];admin=c['ADMIN_ID'];off=0
while True:
 try:
  d=json.load(urllib.request.urlopen(f'https://api.telegram.org/bot{t}/getUpdates?offset={off}&timeout=20',timeout=30))
  for u in d.get('result',[]):
   off=u['update_id']+1;m=u.get('message',{});uid=str(m.get('from',{}).get('id',''));q=m.get('text','')
   if uid!=admin:continue
   out={'/start':'HYTO SSH\n/status\n/restart','/status':subprocess.getoutput('systemctl --type=service --state=running --no-pager|grep -E "xray|ssh|zivpn|iodine|udp"|head -30'),'/restart':'Xray redémarré.'}.get(q,'Commande inconnue.')
   if q=='/restart':subprocess.run('systemctl restart xray',shell=True)
   data=json.dumps({'chat_id':uid,'text':out}).encode();urllib.request.urlopen(urllib.request.Request(f'https://api.telegram.org/bot{t}/sendMessage',data=data,headers={'Content-Type':'application/json'}))
 except Exception:time.sleep(3)
PY
cat >$BASE/hyto-telegram.service <<EOF
[Unit]
After=network-online.target
[Service]
ExecStart=/usr/bin/python3 $BASE/tg-bot.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload;systemctl enable --now hyto-telegram;pause;;4)journalctl -u hyto-telegram --no-pager -n 50;pause;;0)return;;esac; done; }
wa_menu(){ while :; do clear; echo '--- WHATSAPP META CLOUD API ---'; echo '1) Configurer'; echo '2) Vérifier configuration'; echo '3) Informations webhook'; echo '0) Retour'; read -r -p 'Choix: ' c; case $c in 1)read -r -p 'Access Token (0=Retour): ' t;[ "$t" = 0 ]&&continue;read -r -p 'Phone Number ID: ' p;read -r -p 'Verify Token: ' v;printf 'ACCESS_TOKEN=%q\nPHONE_NUMBER_ID=%q\nVERIFY_TOKEN=%q\n' "$t" "$p" "$v">$WA;chmod 600 $WA;echo 'Un domaine HTTPS public est nécessaire pour le webhook.';pause;;2)[ -f "$WA" ]&&echo Configuré||echo Non configuré;pause;;3)echo 'Webhook attendu: https://TON-DOMAINE/hyto/whatsapp';echo 'HTTPS public + certificat TLS requis.';pause;;0)return;;esac;done; }
status_menu(){ clear;for s in ssh xray zivpn iodined udp-custom udpgw hyto-telegram;do printf '%-18s' "$s";systemctl is-active --quiet "$s"&&echo OK||echo OFF;done;pause; }
backup(){ mkdir -p "$BASE/backups";tar -czf "$BASE/backups/hyto-$(date +%Y%m%d-%H%M%S).tgz" "$BASE" "$XR" 2>/dev/null||true;echo 'Sauvegarde créée.';pause; }
menu(){ 
    verify_license
    clear;echo '╔══════════════════════════════════════╗';echo '║              HYTO SSH                ║';echo '╚══════════════════════════════════════╝';echo "IP: $(ip)";echo;echo '1) SSH';echo '2) VLESS / VMess / Trojan';echo '3) ZIVPN UDP';echo '4) UDP Custom';echo '5) SlowDNS';echo '6) Telegram Bot';echo '7) WhatsApp Bot';echo '8) État des services';echo '9) Sauvegarde';echo '0) Quitter';read -r -p 'Choix: ' c;case $c in 1)ssh_menu;;2)xray_menu;;3)zivpn_menu;;4)udp_menu;;5)slow_menu;;6)tg_menu;;7)wa_menu;;8)status_menu;;9)backup;;0)exit;;esac; 
}
root
if [ "${1:-}" = install ];then setup;exit;fi
[ -x "$BIN" ]||setup
verify_license
while :;do menu;done
