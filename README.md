Scripts to backup and restore LVM root volume on headless server, using fsarchiver.
## Requirement
Scripts only support LVM. We only tested with Ubuntu. Also, the system must have free diskspace to create new LVM volumes: one to store the backup files and another as snapshot. If you use all disk space for LVM, you need to shrink it down. E.g.:
```
sudo ./lvreduce.sh -l 100G
sudo reboot

```
Note: `lvreduce` creates initramfs program to shrink root filesystem at boot. You must update initramfs again after reboot to restore old initramfs.
```
sudo update-initramfs -u
```
## Usage
- Create backup file

    ```
    sudo ./backup_w_fsarchiver.sh -b -n fresh_u16_04
    ```
-  When the system is messed up, just restore backup
    ```
    sudo ./backup_w_fsarchiver.sh -r -n fresh_u16_04
    sudo reboot
    ```

For more details on each scripts, run `./<script_name> -h`.

