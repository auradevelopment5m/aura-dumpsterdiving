fx_version 'cerulean'
games { 'gta5' }
lua54 'yes'
name 'aura-dumpsterdiving'
author 'Aura Development'
description 'Trash Searching Script By Aura Development'
version '2.0'

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
