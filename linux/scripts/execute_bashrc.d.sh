
# Add .bashrc.d initialization into .bashrc
echo "
# Initialize .bashrc.d
for file in ~/.bashrc.d/*.sh; do
    source \"\$file\"
done
" >> ~/.bashrc
