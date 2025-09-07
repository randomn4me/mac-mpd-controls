import Foundation
import AppKit
import Carbon

public class MediaKeyHandler {
    private let mpdClient: MPDClient
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isListening = false
    
    public init(mpdClient: MPDClient) {
        self.mpdClient = mpdClient
    }
    
    deinit {
        stopListening()
    }
    
    public func startListening() {
        guard !isListening else { return }
        
        let eventMask = CGEventMask(1 << CGEventType.systemDefined.rawValue)
        
        // Create event tap callback
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            
            let handler = Unmanaged<MediaKeyHandler>.fromOpaque(refcon).takeUnretainedValue()
            
            if type == .tapDisabledByTimeout {
                handler.restartEventTap()
                return Unmanaged.passUnretained(event)
            }
            
            guard type == .systemDefined else {
                return Unmanaged.passUnretained(event)
            }
            
            let nsEvent = NSEvent(cgEvent: event)
            
            if let nsEvent = nsEvent,
               nsEvent.type == .systemDefined,
               nsEvent.subtype.rawValue == 8 {
                
                let keyCode = ((nsEvent.data1 & 0xFFFF0000) >> 16)
                let keyFlags = (nsEvent.data1 & 0x0000FFFF)
                let keyState = ((keyFlags & 0xFF00) >> 8) == 0xA
                let keyRepeat = (keyFlags & 0x1) > 0
                
                if keyState && !keyRepeat {
                    switch Int32(keyCode) {
                    case NX_KEYTYPE_PLAY:
                        handler.handlePlayPause()
                        return nil
                    case NX_KEYTYPE_FAST, NX_KEYTYPE_NEXT:
                        handler.handleNext()
                        return nil
                    case NX_KEYTYPE_REWIND, NX_KEYTYPE_PREVIOUS:
                        handler.handlePrevious()
                        return nil
                    default:
                        break
                    }
                }
            }
            
            return Unmanaged.passUnretained(event)
        }
        
        // Create event tap
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: refcon
        )
        
        guard let eventTap = eventTap else {
            print("Failed to create event tap. Make sure the app has accessibility permissions.")
            requestAccessibilityPermissions()
            return
        }
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource = runLoopSource else {
            print("Failed to create run loop source")
            return
        }
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        isListening = true
        print("Media key handler started listening")
    }
    
    public func stopListening() {
        guard isListening else { return }
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        isListening = false
        
        print("Media key handler stopped listening")
    }
    
    private func restartEventTap() {
        guard let eventTap = eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    private func handlePlayPause() {
        Task { @MainActor in
            mpdClient.toggle()
        }
    }
    
    private func handleNext() {
        Task { @MainActor in
            mpdClient.next()
        }
    }
    
    private func handlePrevious() {
        Task { @MainActor in
            mpdClient.previous()
        }
    }
    
    private func requestAccessibilityPermissions() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "MPD Controls needs accessibility permissions to listen to media keys. Please grant permission in System Settings > Privacy & Security > Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}