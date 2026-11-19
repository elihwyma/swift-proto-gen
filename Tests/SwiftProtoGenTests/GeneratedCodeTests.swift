import Foundation
import SwiftProtoGen
import Testing

@Test func binaryRoundTrip() throws {
    let person = Example_Person.with {
        $0.fullName = "Ada Lovelace"
        $0.id = 1815
        $0.emails = ["ada@example.com"]
        $0.status = .active
        $0.balance = .with {
            $0.currencyCode = "GBP"
            $0.units = 42
        }
        $0.createdAt = Google_Protobuf_Timestamp(seconds: 1_000, nanos: 0)
        $0.nickname = "Ada"
        $0.addresses["home"] = .with { $0.postalCode = "W1" }
        $0.phoneNumber = "555-0100"
    }

    let decoded = try Example_Person(serializedBytes: person.serializedBytes() as [UInt8])

    #expect(decoded == person)
    #expect(decoded.contact == .phoneNumber("555-0100"))
}

@Test func proto3OptionalTracksPresence() {
    var person = Example_Person()
    #expect(!person.hasNickname)
    person.nickname = ""
    #expect(person.hasNickname)
}

@Test func jsonUsesProtoJSONNames() throws {
    let person = Example_Person.with {
        $0.fullName = "Ada"
        $0.status = .suspended
    }

    let json = try person.jsonString()

    #expect(json.contains(#""fullName":"Ada""#))
    #expect(json.contains(#""status":"STATUS_SUSPENDED""#))
    #expect(try Example_Person(jsonString: json) == person)
}

@Test func typesFromDifferentDescriptorSetsInteroperate() throws {
    let price = Example_Money.with { $0.units = 3 }
    let item = Inventory_Item.with {
        $0.sku = "A-1"
        $0.price = price
    }
    let widget = Editions_Widget.with { $0.price = price }

    #expect(try Inventory_Item(serializedBytes: item.serializedBytes() as [UInt8]).price == price)
    #expect(widget.price == item.price)
}

@Test func editionsFeaturesAreApplied() {
    var widget = Editions_Widget()
    #expect(!widget.hasName)
    widget.name = ""
    #expect(widget.hasName)
    widget.count = 0
    #expect(widget.textFormatString() == #"name: """# + "\n")
}

@Test func protoNamesMatchTheDescriptors() {
    #expect(Example_Person.protoMessageName == "example.Person")
    #expect(Example_Person.Address.protoMessageName == "example.Person.Address")
    #expect(Inventory_Item.protoMessageName == "inventory.Item")
}

@Test func protoSourcesAreCompiled() throws {
    let gadget = Gadgets_Gadget.with {
        $0.name = "Sprocket"
        $0.madeAt = Google_Protobuf_Timestamp(seconds: 1_000, nanos: 0)
    }

    #expect(Gadgets_Gadget.protoMessageName == "gadgets.Gadget")
    #expect(try Gadgets_Gadget(serializedBytes: gadget.serializedBytes() as [UInt8]) == gadget)
}
