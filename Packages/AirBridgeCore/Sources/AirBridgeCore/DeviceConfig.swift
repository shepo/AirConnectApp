import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A speaker as recorded in airupnp's `config.xml`.
public struct ConfiguredDevice: Equatable, Sendable {
    public var udn: String
    public var name: String
    public var mac: String?
    public var enabled: Bool

    public init(udn: String, name: String, mac: String?, enabled: Bool) {
        self.udn = udn
        self.name = name
        self.mac = mac
        self.enabled = enabled
    }
}

/// Reads and edits airupnp's config file without disturbing anything AirBridge
/// doesn't own. airupnp's shape (from `-i`):
///
///     <airupnp>
///       <common> … <enabled>1</enabled> … </common>
///       <device><udn>uuid:RINCON_…</udn><name>Kitchen+</name><mac>…</mac><enabled>1</enabled></device>
///     </airupnp>
///
/// `<enabled>` in `<common>` is the default for speakers airupnp finds later.
public struct DeviceConfig {
    private var document: XMLDocument

    public init(data: Data) throws {
        document = try XMLDocument(data: data, options: [])
        guard document.rootElement() != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    /// A config holding only AirBridge's default for new speakers.
    public static func empty(newSpeakersEnabled: Bool) -> DeviceConfig {
        let root = XMLElement(name: "airupnp")
        let doc = XMLDocument(rootElement: root)
        doc.version = "1.0"
        doc.characterEncoding = "UTF-8"
        var config = try! DeviceConfig(data: doc.xmlData)
        config.newSpeakersEnabled = newSpeakersEnabled
        return config
    }

    public var data: Data {
        document.xmlData(options: [.nodePrettyPrint])
    }

    private var root: XMLElement { document.rootElement()! }

    /// XMLDocument is a class; copy it before the first edit so copies of a
    /// DeviceConfig behave like values.
    private mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&document) {
            document = document.copy() as! XMLDocument
        }
    }

    public var newSpeakersEnabled: Bool {
        get {
            guard let common = root.elements(forName: "common").first,
                  let value = common.elements(forName: "enabled").first?.stringValue
            else { return true } // airupnp's own default
            return Self.bool(value)
        }
        set {
            makeUnique()
            let common = root.elements(forName: "common").first ?? {
                let element = XMLElement(name: "common")
                root.insertChild(element, at: 0)
                return element
            }()
            Self.set(child: "enabled", of: common, to: newValue ? "1" : "0")
        }
    }

    public var devices: [ConfiguredDevice] {
        let fallback = newSpeakersEnabled
        return root.elements(forName: "device").compactMap { element in
            guard let udn = Self.text("udn", in: element), !udn.isEmpty else { return nil }
            let enabled = Self.text("enabled", in: element).map(Self.bool) ?? fallback
            return ConfiguredDevice(
                udn: udn,
                name: Self.text("name", in: element) ?? udn,
                mac: Self.text("mac", in: element),
                enabled: enabled
            )
        }
    }

    /// Switches one speaker on or off. Returns false if it isn't in the file.
    @discardableResult
    public mutating func setEnabled(_ enabled: Bool, udn: String) -> Bool {
        makeUnique()
        guard let element = deviceElement(udn: udn) else { return false }
        Self.set(child: "enabled", of: element, to: enabled ? "1" : "0")
        return true
    }

    /// Adds speakers from another config (a fresh `-i` scan) that this one hasn't
    /// seen, switched on or off by `newSpeakersEnabled`. Existing speakers keep
    /// their setting. Returns the udns added.
    @discardableResult
    public mutating func merge(discovered other: DeviceConfig) -> [String] {
        makeUnique()
        var added: [String] = []
        let enabled = newSpeakersEnabled
        for device in other.devices where deviceElement(udn: device.udn) == nil {
            let element = XMLElement(name: "device")
            element.addChild(XMLElement(name: "udn", stringValue: device.udn))
            element.addChild(XMLElement(name: "name", stringValue: device.name))
            if let mac = device.mac {
                element.addChild(XMLElement(name: "mac", stringValue: mac))
            }
            element.addChild(XMLElement(name: "enabled", stringValue: enabled ? "1" : "0"))
            root.addChild(element)
            added.append(device.udn)
        }
        return added
    }

    private func deviceElement(udn: String) -> XMLElement? {
        root.elements(forName: "device").first { Self.text("udn", in: $0) == udn }
    }

    private static func text(_ name: String, in element: XMLElement) -> String? {
        element.elements(forName: name).first?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func set(child name: String, of element: XMLElement, to value: String) {
        if let existing = element.elements(forName: name).first {
            existing.stringValue = value
        } else {
            element.addChild(XMLElement(name: name, stringValue: value))
        }
    }

    private static func bool(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return v == "1" || v == "true" || v == "yes"
    }
}
