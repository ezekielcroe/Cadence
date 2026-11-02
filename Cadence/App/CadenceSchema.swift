//
//  CadenceSchema.swift
//  Cadence
//
//  The single list of SwiftData models. The app, SwiftUI previews and the
//  test target all build their containers from here, so a model can never
//  be used by one of them and missing from another.
//
//  Adding a model? Add it to `models` and nowhere else.
//

import Foundation
import SwiftData

enum CadenceSchema {

    static var models: [any PersistentModel.Type] { [
        Activity.self,
        ActivitySet.self,
        TimeBlock.self,
        TimeBlockRule.self,
        Remark.self,
        DayNote.self,
        DailySummary.self,   // was missing: HistoryManager inserts it on every block save
    ] }

    static var schema: Schema { Schema(models) }

    /// Builds a container for the app (on disk) or for previews/tests (in memory).
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Self.schema
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)]
        )
    }
}
