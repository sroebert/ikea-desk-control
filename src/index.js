#!/usr/bin/env node

import DeskManager from './desk-manager'
import fs from 'fs'

fs.readFile(process.env.CONFIG_FILE || 'data/config.json', (err, data) => {
	if (err) {
		console.log(`Failed to load config json: ${err}`)
		return
	}

	let config = null
	try {
		config = JSON.parse(data)
	} catch (jsonErr) {
		console.log(`Failed to parse config json: ${jsonErr}`)
		return
	}
	
	const manager = new DeskManager({
		dataStorageDir: process.env.DATA_DIR || './data',
		deskAddress: config.deskAddress,
		deskPositionOffset: config.deskPositionOffset,
		deskPositionMax: config.deskPositionMax,
		mqttUrl: config.mqttUrl,
		mqttUsername: config.mqttUsername,
		mqttPassword: config.mqttPassword
	})
	manager.start()
})
