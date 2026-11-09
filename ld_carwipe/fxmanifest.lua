fx_version 'cerulean'
game 'gta5'

name 'ld_carwipe'
author 'LD Scripts'
version '2.0.0'
description 'Automatic vehicle cleanup with warnings, smart filters and zero client load'
repository 'https://github.com/LucaNL/LD-CarWipe'

lua54 'yes'
server_only 'yes'

server_scripts {
    'config.lua',
    'locales/*.lua',
    'server/main.lua',
    'server/integrations.lua',
    'server/commands.lua',
}

dependencies {
    '/onesync',
}
