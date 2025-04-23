fx_version 'cerulean'
games { 'gta5' }
lua54 'yes'
author 'ZDevelopment'
description 'Trash Searching Script By ZDevelopment'
version '1.0.0'

server_scripts {
    'config.lua',
    "server/**.lua",
    
}

shared_scripts {
    'shared/modules.lua',
    '@ox_lib/init.lua'
}

client_scripts {
    'config.lua',
    "client/**.lua",
}

dependencies {
    'qb-core'
}
