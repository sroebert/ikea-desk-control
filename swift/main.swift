//
//  main.swift
//  IKEADeskControl
//
//  Created by Steven Roebert on 13/05/2020.
//  Copyright © 2020 Steven Roebert. All rights reserved.
//

import Foundation

signal(SIGINT, SIG_IGN)

let url = URL(fileURLWithPath: "./data/config.json")
do {
    _ = try Data(contentsOf: url)
} catch {
    print("Missing config file")
    exit(1)
}

let task = Process()
task.launchPath = "/bin/bash"
task.environment = [
    "PATH": "/usr/local/bin:/usr/bin:/bin",
    "NVM_DIR": "$HOME/.nvm"
]
task.arguments = ["-c", "npm start"]


let sigintSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigintSrc.setEventHandler {
    task.terminate()
    exit(0)
}
sigintSrc.resume()

task.launch()
task.waitUntilExit()
exit(task.terminationStatus)
