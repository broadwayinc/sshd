# sshd

`sshd` opens an ssh session to a remote host using a saved key, user and host, optionally starting in a given folder.

## Install

From the directory containing `sshd.sh`, run:

```bash
./install-sshd.sh
```

This installs the `sshd` command in `~/.local/bin` (or `$XDG_BIN_HOME` if set) and optionally enables tab completion in `~/.bashrc` (`--completion` / `--no-completion` skip the question). If that directory is not in your `PATH`, add it as instructed by the installer and open a new terminal. Make sure `~/.local/bin` comes before `/usr/sbin` in `PATH`, otherwise the OpenSSH daemon binary of the same name may be found first.

## Configure

Connection settings are stored as named **targets** in `sshd.conf`, in the same directory as `sshd.sh`. There are no built-in defaults: the first time you run `sshd` with no targets, it asks for the values and saves them.

```bash
sshd -c            # asks for a name, key file, username, host and start directory
sshd -c staging    # same, for the target named "staging"
sshd -T            # list targets
```

When you add a target after the first, `sshd` asks whether to make it the default. If no default is set, the first target in the file is the default. You can also edit `sshd.conf` by hand:

```ini
default = work

[work]
key = ~/.ssh/work.pem
user = ubuntu
host = work.example.com
dir = ~/projects

[staging]
key = ~/.ssh/staging.pem
user = deploy
host = staging.example.com
```

`default` must come before the first section. Values may start with `~` or `$HOME`. A target needs `key`, `user` and `host`. `dir` is optional: the remote folder to start in when you give no folder on the command line (a folder argument overrides it; a missing folder falls back to the remote home). `dir` is a remote path, so `~` is not expanded locally.

To use a config file at another location, set `SSHD_CONF`.

## Use

```bash
sshd                    # connect to the default target
sshd -t staging         # connect to another target
sshd ~/projects         # start in a remote folder
sshd -t staging /var/www
sshd -u root            # override user (also -i key, -H host)
sshd -h                 # help
```

If the folder does not exist on the remote host, you are logged in to the home folder. A `~` typed unquoted is expanded by your local shell; `sshd` also tries the same path under the remote home. Quote it (`'~/x'`) to send it as is.
