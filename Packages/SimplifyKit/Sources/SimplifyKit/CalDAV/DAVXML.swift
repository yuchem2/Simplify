import Foundation

/// A parsed XML element, with namespaces resolved. Enough of a DOM for WebDAV multistatus bodies.
struct DAVNode {
    static let dav = "DAV:"
    static let caldav = "urn:ietf:params:xml:ns:caldav"
    static let apple = "http://apple.com/ns/ical/"

    var namespace: String
    var name: String
    var attributes: [String: String] = [:]
    var children: [DAVNode] = []
    var text = ""

    func child(_ namespace: String, _ name: String) -> DAVNode? {
        children.first { $0.namespace == namespace && $0.name == name }
    }

    func children(_ namespace: String, _ name: String) -> [DAVNode] {
        children.filter { $0.namespace == namespace && $0.name == name }
    }

    /// The first element with this name anywhere below, depth first.
    func descendant(_ namespace: String, _ name: String) -> DAVNode? {
        for node in children {
            if node.namespace == namespace && node.name == name { return node }
            if let found = node.descendant(namespace, name) { return found }
        }
        return nil
    }

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func parse(_ data: Data) throws -> DAVNode {
        let delegate = Builder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { throw CalendarSyncError.invalidResponse }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var stack: [DAVNode] = []
        var root: DAVNode?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            stack.append(DAVNode(namespace: namespaceURI ?? "", name: name, attributes: attributes))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if !stack.isEmpty { stack[stack.count - 1].text += string }
        }

        func parser(_ parser: XMLParser, foundCDATA data: Data) {
            if !stack.isEmpty { stack[stack.count - 1].text += String(decoding: data, as: UTF8.self) }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard let done = stack.popLast() else { return }
            if stack.isEmpty { root = done } else { stack[stack.count - 1].children.append(done) }
        }
    }
}

/// One `<response>` of a 207 Multi-Status body.
struct DAVResponse {
    var href: String
    /// The response's own status (`404` for a deleted member in a sync report), if it has one.
    var status: Int?
    /// The properties that came back with 200.
    var properties: [DAVNode]

    func property(_ namespace: String, _ name: String) -> DAVNode? {
        properties.first { $0.namespace == namespace && $0.name == name }
    }

    static func multistatus(_ data: Data) throws -> (responses: [DAVResponse], syncToken: String?) {
        let root = try DAVNode.parse(data)
        guard root.namespace == DAVNode.dav, root.name == "multistatus" else { throw CalendarSyncError.invalidResponse }
        let responses = root.children(DAVNode.dav, "response").compactMap { node -> DAVResponse? in
            guard let href = node.child(DAVNode.dav, "href")?.trimmedText else { return nil }
            let found = node.children(DAVNode.dav, "propstat")
                .filter { status($0.child(DAVNode.dav, "status")?.text) == 200 }
                .flatMap { $0.child(DAVNode.dav, "prop")?.children ?? [] }
            return DAVResponse(href: href, status: status(node.child(DAVNode.dav, "status")?.text), properties: found)
        }
        return (responses, root.child(DAVNode.dav, "sync-token")?.trimmedText)
    }

    /// `HTTP/1.1 404 Not Found` → 404.
    static func status(_ line: String?) -> Int? {
        guard let line else { return nil }
        let parts = line.split(separator: " ")
        return parts.count >= 2 ? Int(parts[1]) : nil
    }
}

extension String {
    /// Safe inside XML text.
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
