import Foundation
import AppKit
import Carbon

public final class MediaKeyHandler: @unchecked Sendable {
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
        guard !isListening else { 
            Logger.shared.log("MediaKeyHandler: Already listening, skipping")
            return 
        }
        
        let eventMask = CGEventMask(1 << 14) // System defined event type
        Logger.shared.log("MediaKeyHandler: Creating event tap with mask: \(eventMask)")
        
        // Create event tap callback
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { 
                Logger.shared.log("MediaKeyHandler: No refcon in callback")
                return Unmanaged.passUnretained(event) 
            }
            
            let handler = Unmanaged<MediaKeyHandler>.fromOpaque(refcon).takeUnretainedValue()
            
            if type == .tapDisabledByTimeout {
                Logger.shared.log("MediaKeyHandler: Event tap disabled by timeout, restarting")
                handler.restartEventTap()
                return Unmanaged.passUnretained(event)
            }
            
            Logger.shared.log("MediaKeyHandler: Received event - type: \(type.rawValue), expecting: 14")
            
            // Check if it's a system defined event (raw value 14)
            guard type.rawValue == 14 else {
                return Unmanaged.passUnretained(event)
            }
            
            let nsEvent = NSEvent(cgEvent: event)
            Logger.shared.log("MediaKeyHandler: System defined event detected")
            
            if let nsEvent = nsEvent,
               nsEvent.type == .systemDefined,
               nsEvent.subtype.rawValue == 8 {
                
                let keyCode = ((nsEvent.data1 & 0xFFFF0000) >> 16)
                let keyFlags = (nsEvent.data1 & 0x0000FFFF)
                let keyState = ((keyFlags & 0xFF00) >> 8) == 0xA
                let keyRepeat = (keyFlags & 0x1) > 0
                
                Logger.shared.log("MediaKeyHandler: Media key event - keyCode: \(keyCode), keyState: \(keyState), keyRepeat: \(keyRepeat)")
                
                if keyState && !keyRepeat {
                    switch Int32(keyCode) {
                    case NX_KEYTYPE_PLAY:
                        Logger.shared.log("MediaKeyHandler: Play/Pause key pressed")
                        handler.handlePlayPause()
                        return nil
                    case NX_KEYTYPE_FAST, NX_KEYTYPE_NEXT:
                        Logger.shared.log("MediaKeyHandler: Next key pressed")
                        handler.handleNext()
                        return nil
                    case NX_KEYTYPE_REWIND, NX_KEYTYPE_PREVIOUS:
                        Logger.shared.log("MediaKeyHandler: Previous key pressed")
                        handler.handlePrevious()
                        return nil
                    default:
                        Logger.shared.log("MediaKeyHandler: Unhandled media key: \(keyCode)")
                        break
                    }
                }
            } else {
                Logger.shared.log("MediaKeyHandler: Event not a media key - type: \(nsEvent?.type.rawValue ?? 999), subtype: \(nsEvent?.subtype.rawValue ?? 999)")
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
            Logger.shared.log("MediaKeyHandler: Failed to create event tap. Make sure the app has accessibility permissions.")
            Task { @MainActor in
                requestAccessibilityPermissions()
            }
            return
        }
        
        Logger.shared.log("MediaKeyHandler: Event tap created successfully")
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource = runLoopSource else {
            Logger.shared.log("MediaKeyHandler: Failed to create run loop source")
            return
        }
        
        Logger.shared.log("MediaKeyHandler: Run loop source created successfully")
        
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        isListening = true
        Logger.shared.log("MediaKeyHandler: Successfully started listening for media keys")
    }
    
    public func stopListening() {
        guard isListening else { 
            Logger.shared.log("MediaKeyHandler: Not currently listening, skipping stop")
            return 
        }
        
        Logger.shared.log("MediaKeyHandler: Stopping media key listening...")
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            Logger.shared.log("MediaKeyHandler: Event tap disabled and invalidated")
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            Logger.shared.log("MediaKeyHandler: Run loop source removed")
        }
        
        eventTap = nil
        runLoopSource = nil
        isListening = false
        
        Logger.shared.log("MediaKeyHandler: Successfully stopped listening for media keys")
    }
    
    private func restartEventTap() {
        guard let eventTap = eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    private func handlePlayPause() {
        Logger.shared.log("MediaKeyHandler: Handling play/pause command")
        Task { @MainActor in
            mpdClient.toggle()
        }
    }
    
    private func handleNext() {
        Logger.shared.log("MediaKeyHandler: Handling next command")
        Task { @MainActor in
            mpdClient.next()
        }
    }
    
    private func handlePrevious() {
        Logger.shared.log("MediaKeyHandler: Handling previous command")
        Task { @MainActor in
            mpdClient.previous()
        }
    }
    
    @MainActor
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