#!/usr/bin/env ruby

require 'mysql2'
require 'net/http'
require 'open-uri'

domain = ARGV[0]

@server_admin = "somebody@somewhere.com"
db_host = "xx.xxx.xx.xxx"
db_webhost = "xx.xxx.xx.xxx"
db_user = "xxxxxxxxxxxxxxxxx"
db_pass = "xxxxxxxxxxxxxxxxx"
db_name = domain.split(".")
db_name = db_name[0]
db_name = db_name[0,16] #mysql don't like usernames longer than 16 characters

puts "Creating database"
client = Mysql2::Client.new(:host => db_host, :username => db_user, :password => db_pass)
client.query("DROP DATABASE IF EXISTS #{db_name}")
client.query("CREATE DATABASE #{db_name}")
client.query("GRANT ALL ON #{db_name}.* TO '#{db_name}'@'#{db_webhost}' IDENTIFIED BY '#{db_pass}';")
client.close

puts "Creating Apache configuration"
File.open("/etc/apache2/sites-available/#{domain}", "w") do |f|  
	f.puts "<VirtualHost *:80>"
	f.puts "	ServerAdmin #{server_admin}"
	f.puts "	ServerName #{domain}"
	f.puts "	ServerAlias www.#{domain}"
	f.puts "	DocumentRoot /var/www/#{domain}/public_html/"
	f.puts "	ErrorLog /var/log/apache2/error.log"
	f.puts "	CustomLog /var/log/apache2/access.log combined"
	f.puts "</VirtualHost>"
end  

`ln -s /etc/apache2/sites-available/#{domain} /etc/apache2/sites-enabled/#{domain}`
`/bin/mkdir -p /var/www/#{domain}/public_html`
`/bin/mkdir /var/www/#{domain}/logs`
`/bin/chown -R www-data.www-data /var/www/#{domain}`

puts "Adding #{domain} to Apache"
`/usr/sbin/a2ensite #{domain}`

puts "Restarting Apache"
`/etc/init.d/apache2 restart`

puts "Downloading Wordpress for #{domain}."
Net::HTTP.start("wordpress.org") do |http|
    resp = http.get("/latest.zip")
    open("/var/www/#{domain}/public_html/latest.zip", "wb") do |file|
        file.write(resp.body)
    end
end

puts "Unzipping Wordpress"
`cd /var/www/#{domain}/public_html/ ; /usr/bin/unzip /var/www/#{domain}/public_html/latest.zip`
`/bin/mv /var/www/#{domain}/public_html/wordpress/* /var/www/#{domain}/public_html/`

puts "Cleaning up"
`/bin/rmdir /var/www/#{domain}/public_html/wordpress`
`/bin/rm /var/www/#{domain}/public_html/latest.zip`

puts "Grabbing random security salt for wp-config.php"
document = open('https://api.wordpress.org/secret-key/1.1/salt/').read

puts "Preparing wp-config-sample.php"
myfile = "/var/www/#{domain}/public_html/wp-config-sample.php"
text = File.read(myfile)
text = text.gsub(/database_name_here/, "#{db_name}")
text = text.gsub(/username_here/, "#{db_name}")
text = text.gsub(/password_here/, "#{db_pass}")
text = text.gsub("define('AUTH_KEY',         'put your unique phrase here');", "")
text = text.gsub("define('SECURE_AUTH_KEY',  'put your unique phrase here');", "")
text = text.gsub("define('LOGGED_IN_KEY',    'put your unique phrase here');", "")
text = text.gsub("define('NONCE_KEY',        'put your unique phrase here');", "")
text = text.gsub("define('AUTH_SALT',        'put your unique phrase here');", "")
text = text.gsub("define('SECURE_AUTH_SALT', 'put your unique phrase here');", "")
text = text.gsub("define('LOGGED_IN_SALT',   'put your unique phrase here');", "")
text = text.gsub("define('NONCE_SALT',       'put your unique phrase here');", document)
text.delete!("\C-M") # It's gay that I have to do this but whatevs.
replace = text.gsub(/localhost/, "#{db_host}")
File.open(myfile, "w") {|file| file.puts replace}

puts "Renaming wp-config-sample.php to wp-config.php"
`/bin/mv #{myfile} /var/www/#{domain}/public_html/wp-config.php`
`/bin/chown www-data.www-data -R /var/www/#{domain}/`

puts "Done"
