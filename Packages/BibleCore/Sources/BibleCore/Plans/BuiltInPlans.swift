import Foundation

/// The plans that ship with the app.
///
/// These are the well-worn ones people actually memorize together. They are
/// code, not content, so they can be corrected in a release without touching a
/// user's own plans; a user who does not want one can hide it.
public enum BuiltInPlans {
    public static let all: [MemoryPlan] = [
        romanRoad,
        sermonOnTheMount,
        theLordsPrayer,
        greatCommission,
        fruitOfTheSpirit,
        shepherdAndComfort,
    ]

    public static func plan(id: String) -> MemoryPlan? { all.first { $0.id == id } }

    // MARK: - Plans

    /// The classic five-stop presentation of the gospel from Romans.
    public static let romanRoad = MemoryPlan(
        id: "builtin.roman-road",
        title: "The Roman Road",
        summary:
            "Five verses from Romans, in the order they are usually walked through: "
            + "the problem, its cost, God's answer, the response, and the promise.",
        sections: [
            .init(
                id: "builtin.roman-road.s1",
                title: "The Roman Road",
                passages: [
                    PassageRef(BookID("ROM"), 3, 23),
                    PassageRef(BookID("ROM"), 6, 23),
                    PassageRef(BookID("ROM"), 5, 8),
                    PassageRef(BookID("ROM"), 10, 9, 10),
                    PassageRef(BookID("ROM"), 10, 13),
                ]
            )
        ],
        isBuiltIn: true
    )

    /// Matthew 5–7 in full, broken into the sections it is usually taught in.
    public static let sermonOnTheMount = MemoryPlan(
        id: "builtin.sermon-on-the-mount",
        title: "The Sermon on the Mount",
        summary:
            "Matthew 5 through 7, whole. A long plan — the sections are the "
            + "natural resting places rather than a schedule.",
        sections: [
            .init(
                id: "builtin.sotm.beatitudes",
                title: "The Beatitudes",
                passages: [PassageRef(BookID("MAT"), 5, 1, 12)]
            ),
            .init(
                id: "builtin.sotm.salt-and-light",
                title: "Salt and Light",
                passages: [PassageRef(BookID("MAT"), 5, 13, 16)]
            ),
            .init(
                id: "builtin.sotm.law",
                title: "The Law Fulfilled",
                passages: [PassageRef(BookID("MAT"), 5, 17, 48)]
            ),
            .init(
                id: "builtin.sotm.giving-and-prayer",
                title: "Giving and Prayer",
                passages: [PassageRef(BookID("MAT"), 6, 1, 18)]
            ),
            .init(
                id: "builtin.sotm.treasure-and-worry",
                title: "Treasure and Worry",
                passages: [PassageRef(BookID("MAT"), 6, 19, 34)]
            ),
            .init(
                id: "builtin.sotm.judging-and-asking",
                title: "Judging and Asking",
                passages: [PassageRef(BookID("MAT"), 7, 1, 12)]
            ),
            .init(
                id: "builtin.sotm.two-ways",
                title: "The Two Ways",
                passages: [PassageRef(BookID("MAT"), 7, 13, 29)]
            ),
        ],
        isBuiltIn: true
    )

    public static let theLordsPrayer = MemoryPlan(
        id: "builtin.lords-prayer",
        title: "The Lord's Prayer",
        summary: "Matthew's form of the prayer, with Luke's shorter one alongside it.",
        sections: [
            .init(
                id: "builtin.lords-prayer.matthew",
                title: "Matthew's form",
                passages: [PassageRef(BookID("MAT"), 6, 9, 13)]
            ),
            .init(
                id: "builtin.lords-prayer.luke",
                title: "Luke's form",
                passages: [PassageRef(BookID("LUK"), 11, 2, 4)]
            ),
        ],
        isBuiltIn: true
    )

    public static let greatCommission = MemoryPlan(
        id: "builtin.great-commission",
        title: "The Great Commission",
        summary: "The sending, as each of the gospels and Acts records it.",
        sections: [
            .init(
                id: "builtin.commission.all",
                title: "The Great Commission",
                passages: [
                    PassageRef(BookID("MAT"), 28, 18, 20),
                    PassageRef(BookID("MRK"), 16, 15),
                    PassageRef(BookID("LUK"), 24, 46, 48),
                    PassageRef(BookID("ACT"), 1, 8),
                ]
            )
        ],
        isBuiltIn: true
    )

    public static let fruitOfTheSpirit = MemoryPlan(
        id: "builtin.fruit-of-the-spirit",
        title: "Fruit of the Spirit",
        summary: "Galatians 5:22–23, with the verses either side that frame it.",
        passages: [PassageRef(BookID("GAL"), 5, 16, 25)],
        isBuiltIn: true
    )

    public static let shepherdAndComfort = MemoryPlan(
        id: "builtin.shepherd-and-comfort",
        title: "Shepherd and Comfort",
        summary:
            "The passages people reach for in hard seasons: Psalm 23, Psalm 121, "
            + "and Paul on what cannot separate us.",
        sections: [
            .init(
                id: "builtin.comfort.psalm23",
                title: "Psalm 23",
                passages: [PassageRef(.psalms, 23, 1, 6)]
            ),
            .init(
                id: "builtin.comfort.psalm121",
                title: "Psalm 121",
                passages: [PassageRef(.psalms, 121, 1, 8)]
            ),
            .init(
                id: "builtin.comfort.romans8",
                title: "Nothing Can Separate Us",
                passages: [PassageRef(BookID("ROM"), 8, 35, 39)]
            ),
        ],
        isBuiltIn: true
    )
}
