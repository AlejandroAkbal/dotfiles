# https://forums.developer.nvidia.com/t/strange-behaviour-of-low-power-states-on-ubuntu-22-lts/256701

Go to the following directory and remove no persistenced

```bash
sudo nano /lib/systemd/system/nvidia-persistenced.service
```