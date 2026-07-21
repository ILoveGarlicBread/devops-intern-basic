
---

## Scenario 1: The Outbound Block (The "Ping" Test)
**Goal:** Prove that `iptables` can stop traffic from leaving your server by silently dropping ICMP (ping) packets destined for Google's DNS.

1. **Show the baseline (Internet works):**
   ```bash
   ping -c 3 8.8.8.8
   ```
   *(Audience sees 3 successful replies).*

2. **Apply the block:**
   ```bash
   sudo iptables -A OUTPUT -d 8.8.8.8 -j REJECT
   ```

3. **Show the block in action:**
   ```bash
   ping -c 3 8.8.8.8
   ```
   *(Audience sees the terminal hang and report 100% packet loss).*

4. **Remove the block to restore service:**
   ```bash
   sudo iptables -D OUTPUT -d 8.8.8.8 -j REJECT
   ```

---

## Scenario 2: Blocking Incoming Replies (The "One-Way" Ping)
**Goal:** Show how to block incoming traffic specifically. We will allow our ping to reach Google, but block Google's reply from coming back in!

1. **Add a rule to DROP incoming traffic from a specific source (`-s`):**
   ```bash
   sudo iptables -A INPUT -s 8.8.8.8 -j DROP
   ```

2. **Run the ping again (Notice it hangs!):**
   ```bash
   ping -c 3 8.8.8.8
   ```
   *Explain: The ping packets are successfully leaving your server (OUTPUT is clear). However, when Google's server replies, your INPUT chain intercepts the reply and drops it. Your ping command is waiting for a reply that gets thrown in the trash right at the door!*

3. **Verify the rule was added and is catching packets:**
   ```bash
   sudo iptables -L INPUT -v -n --line-numbers
   ```
   *(Point out the non-zero `pkts` counter next to the DROP rule, proving it intercepted the replies).*

4. **Delete the rule using its line number:**
   ```bash
   sudo iptables -D INPUT 1
   ```

---

## Scenario 3: Opening a Specific Port
**Goal:** Show how to explicitly allow web traffic (Port 80) into the server.

1. **Insert an ACCEPT rule at the very top of the chain (`-I` instead of `-A`):**
   ```bash
   sudo iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
   ```
   *Explain: We use `-I INPUT 1` (Insert at position 1) because iptables reads top-down. If we appended it to the bottom, a broader `DROP` rule higher up might block it first!*

---

## ⚠️ Pro-Tip: Rule Persistence
By default, **iptables rules only live in RAM**. If your server reboots or crashes, every rule you just wrote will vanish! 

To make your rules survive a reboot, you must explicitly save them.

**On Ubuntu / Debian:**
1. Install the persistent package:
   ```bash
   sudo apt-get install iptables-persistent
   ```
2. Save your current active rules to the disk:
   ```bash
   sudo netfilter-persistent save
   ```
*(The rules are saved to `/etc/iptables/rules.v4` and will automatically load on the next boot).*

**On CentOS / RHEL:**
```bash
sudo iptables-save > /etc/sysconfig/iptables
```
