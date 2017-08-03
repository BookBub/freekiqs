Vagrant.configure(2) do |config|
  config.vm.box = 'ubuntu/xenial64'

  config.vm.network :private_network, ip: '192.168.33.69'
  config.vm.network :forwarded_port, host: 2202, guest: 22, id: 'ssh', auto_correct: true

  config.vm.synced_folder '.', '/vagrant', type: 'nfs'

  config.vm.provider :virtualbox do |vb|
    vb.name = 'freekiqs'
    vb.memory = 2048
    vb.cpus = 2
  end

  config.vm.provision :shell, inline: <<-SCRIPT
    apt-get update
    apt-get upgrade
    apt-get install -y git gnupg2 redis-server
  SCRIPT

  config.vm.provision :shell, privileged: false, inline: <<-SCRIPT
    gpg --keyserver hkp://pool.sks-keyservers.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
    curl -sSL https://get.rvm.io | bash -s stable --quiet-curl --with-gems=bundler
    source "$HOME/.rvm/scripts/rvm"
    rvm --quiet-curl install 2.3.4
    rvm use 2.3.4 --default
    cd /vagrant
    bundle install --full-index -j4
    echo 'cd /vagrant' >> ~/.bash_profile
  SCRIPT
end
