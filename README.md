> [!IMPORTANT]
> I am not responsible of anything that breaks with this fork, you are using this fork at your responsibility.

# THIS IS ONLY USED FOR ENTERTAINMENT PURPOSES ONLY, DO NOT USE THIS FORK AS YOUR INIT SYSTEM OUTSIDE OF A VM UNLESS YOU KNOW WHAT YOU'RE DOING.

### This fork also removes SystemD's birthDate functionality.

## Add the repo in /etc/pacman.conf

```ini
[malik05]
SigLevel = DatabaseRequired PackageOptional TrustedOnly
Server = https://github.com/malik05051/malik05-repo/releases/latest/download
```

The database is signed, so import the key once:

```sh
curl -LO https://github.com/malik05051/malik05-repo/releases/latest/download/key.asc
sudo pacman-key --add key.asc
sudo pacman-key --lsign-key 9EB820E32291639E0E8A8516B6B763F6A4C101F8
```

Then:

```sh
sudo pacman -Syu systemd-arab-edition systemd-libs-arab-edition \
                 systemd-sysvcompat-arab-edition systemd-resolvconf-arab-edition
```
