//
//  PermissionsManager.swift
//  click
//
//  Created by Pablo Ruiz on 24/8/24.
//

import ApplicationServices
import Foundation

class PermissionsManager {
    static func getStatus() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
