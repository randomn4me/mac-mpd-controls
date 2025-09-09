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
            print("MediaKeyHandler: Already listening, skipping")
            return 
        }
        
        let eventMask = CGEventMask(1 << 14) // System defined event type
        print("MediaKeyHandler: Creating event tap with mask: \(eventMask)")
        
        // Create event tap callback
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { 
                print("MediaKeyHandler: No refcon in callback")
                return Unmanaged.passUnretained(event) 
            }
            
            let handler = Unmanaged<MediaKeyHandler>.fromOpaque(refcon).takeUnretainedValue()
            
            if type == .tapDisabledByTimeout {
                print("MediaKeyHandler: Event tap disabled by timeout, restarting")
                handler.restartEventTap()
                return Unmanaged.passUnretained(event)
            }
            
            print("MediaKeyHandler: Received event - type: \(type.rawValue), expecting: 14")
            
            // Check if it's a system defined event (raw value 14)
            guard type.rawValue == 14 else {
                return Unmanaged.passUnretained(event)
            }
            
            let nsEvent = NSEvent(cgEvent: event)
            print("MediaKeyHandler: System defined event detected")
            
            if let nsEvent = nsEvent,
               nsEvent.type == .systemDefined,
               nsEvent.subtype.rawValue == 8 {
                
                let keyCode = ((nsEvent.data1 & 0xFFFF0000) >> 16)
                let keyFlags = (nsEvent.data1 & 0x0000FFFF)
                let keyState = ((keyFlags & 0xFF00) >> 8) == 0xA
                let keyRepeat = (keyFlags & 0x1) > 0
                
                print("MediaKeyHandler: Media key event - keyCode: \(keyCode), keyState: \(keyState), keyRepeat: \(keyRepeat)")
                
                if keyState && !keyRepeat {
                    switch Int32(keyCode) {
                    case NX_KEYTYPE_PLAY:
                        print("MediaKeyHandler: Play/Pause key pressed")
                        handler.handlePlayPause()
                        return nil
                    case NX_KEYTYPE_FAST, NX_KEYTYPE_NEXT:
                        print("MediaKeyHandler: Next key pressed")
                        handler.handleNext()
                        return nil
                    case NX_KEYTYPE_REWIND, NX_KEYTYPE_PREVIOUS:
                        print("MediaKeyHandler: Previous key pressed")
                        handler.handlePrevious()
                        return nil
                    default:
                        print("MediaKeyHandler: Unhandled media key: \(keyCode)")
                        break
                    }
                }
            } else {
                print("MediaKeyHandler: Event not a media key - type: \(nsEvent?.type.rawValue ?? 999), subtype: \(nsEvent?.subtype.rawValue ?? 999)")
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
            print("MediaKeyHandler: Failed to create event tap. Make sure the app has accessibility permissions.")
            Task { @MainActor in
                requestAccessibilityPermissions()
            }
            return
        }
        
        print("MediaKeyHandler: Event tap created successfully")
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource = runLoopSource else {
            print("MediaKeyHandler: Failed to create run loop source")
            return
        }
        
        print("MediaKeyHandler: Run loop source created successfully")
        
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        isListening = true
        print("MediaKeyHandler: Successfully started listening for media keys")
    }
    
    public func stopListening() {
        guard isListening else { 
            print("MediaKeyHandler: Not currently listening, skipping stop")
            return 
        }
        
        print("MediaKeyHandler: Stopping media key listening...")
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            print("MediaKeyHandler: Event tap disabled and invalidated")
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            print("MediaKeyHandler: Run loop source removed")
        }
        
        eventTap = nil
        runLoopSource = nil
        isListening = false
        
        print("MediaKeyHandler: Successfully stopped listening for media keys")
    }
    
    private func restartEventTap() {
        guard let eventTap = eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    private func handlePlayPause() {
        print("MediaKeyHandler: Handling play/pause command")
        Task { @MainActor in
            mpdClient.toggle()
        }
    }
    
    private func handleNext() {
        print("MediaKeyHandler: Handling next command")
        Task { @MainActor in
            mpdClient.next()
        }
    }
    
    private func handlePrevious() {
        print("MediaKeyHandler: Handling previous command")
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