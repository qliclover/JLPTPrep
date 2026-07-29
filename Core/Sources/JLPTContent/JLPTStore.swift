import Foundation
import SwiftData

/// 全 App 的 SwiftData schema 与容器构造。
public enum JLPTStore {
    /// 所有 @Model 类型。加新实体必须登记到这里，否则运行时才会炸。
    public static let models: [any PersistentModel.Type] = [
        VocabEntity.self,
        GrammarEntity.self,
        ReviewItemEntity.self,
        ReviewLogEntity.self,
        ImportRecordEntity.self,
        BookEntity.self,
        NoteEntity.self,
        VocabPackEntity.self,
        ExamEntity.self,
        ExamQuestionEntity.self,
    ]

    public static var schema: Schema { Schema(models) }

    public static func container(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        )
    }
}
