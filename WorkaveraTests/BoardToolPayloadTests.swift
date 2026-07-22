import XCTest
@testable import Workavera

final class BoardToolPayloadTests: XCTestCase {
    private func json(_ string: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(string.utf8))
    }

    func testSearchProjectsDecodesProjectList() throws {
        let output = try json(#"""
        [
          {
            "id": "proj-1",
            "name": "Website",
            "description": "Marketing site",
            "archived": false,
            "currentActorRole": "owner",
            "states": [
              {"id": "s1", "name": "Todo", "color": "#3b82f6", "category": "pending", "taskCount": 3},
              {"id": "s2", "name": "Done", "color": "#22c55e", "category": "completed", "taskCount": 5}
            ],
            "labels": [{"id": "l1", "name": "Bug", "color": "#ef4444"}],
            "members": [{"id": "u1", "name": "Ada", "avatar": "ada.png", "collectionId": "users", "role": "admin"}]
          }
        ]
        """#)

        let payload = try XCTUnwrap(BoardToolPayload(toolName: "board_search_projects", output: output))

        XCTAssertEqual(payload.projects.count, 1)
        let project = payload.projects[0]
        XCTAssertEqual(project.name, "Website")
        XCTAssertEqual(project.role, "owner")
        XCTAssertEqual(project.taskCount, 8)
        XCTAssertEqual(project.states.count, 2)
        XCTAssertEqual(project.states[0].color, "#3b82f6")
        XCTAssertEqual(project.labels.first?.name, "Bug")
        XCTAssertEqual(project.members.first?.role, "admin")
    }

    func testGetProjectDecodesSingleProject() throws {
        let output = try json(#"{"id":"proj-1","name":"Website","archived":true,"states":[]}"#)

        let payload = try XCTUnwrap(BoardToolPayload(toolName: "board_get_project", output: output))

        XCTAssertEqual(payload.projects.count, 1)
        XCTAssertTrue(payload.projects[0].archived)
    }

    func testSearchTasksDecodesTaskFields() throws {
        let output = try json(#"""
        {
          "states": [],
          "tasks": [
            {
              "id": "task-1",
              "title": "Ship v1",
              "description": "Release",
              "priority": "urgent",
              "dueDate": "2020-01-01",
              "project": {"id": "proj-1", "name": "Website"},
              "state": {"id": "s1", "name": "Todo", "color": "#3b82f6"},
              "labels": [{"id": "l1", "name": "Bug", "color": "#ef4444"}],
              "assignees": [{"id": "u1", "name": "Ada", "avatar": "ada.png"}]
            }
          ]
        }
        """#)

        let payload = try XCTUnwrap(BoardToolPayload(toolName: "board_search_tasks", output: output))

        XCTAssertEqual(payload.tasks.count, 1)
        let task = payload.tasks[0]
        XCTAssertEqual(task.title, "Ship v1")
        XCTAssertEqual(task.priority, .urgent)
        XCTAssertTrue(task.isOverdue)
        XCTAssertEqual(task.projectName, "Website")
        XCTAssertEqual(task.stateName, "Todo")
        XCTAssertEqual(task.assignees.first?.name, "Ada")
    }

    func testListTemplatesDecodesCounts() throws {
        let output = try json(#"""
        [{"id":"tpl-1","name":"Sprint","description":"Agile","states":[{},{}],"labels":[{}]}]
        """#)

        let payload = try XCTUnwrap(BoardToolPayload(toolName: "board_list_templates", output: output))

        XCTAssertEqual(payload.templates.first?.stateCount, 2)
        XCTAssertEqual(payload.templates.first?.labelCount, 1)
    }

    func testBatchMutationDecodesEnvelope() throws {
        let output = try json(#"""
        {
          "ok": false, "total": 2, "succeeded": 1, "failed": 1,
          "results": [
            {"index": 0, "ok": true, "result": {"ok": true, "action": "created", "resourceType": "task", "id": "t1", "name": "Task A"}},
            {"index": 1, "ok": false, "error": "state not found"}
          ]
        }
        """#)

        let payload = try XCTUnwrap(BoardToolPayload(toolName: "board_create_task", output: output))

        XCTAssertTrue(payload.isBatchMutation)
        XCTAssertEqual(payload.mutationTotal, 2)
        XCTAssertEqual(payload.mutationSucceeded, 1)
        XCTAssertEqual(payload.mutationItems[0].name, "Task A")
        XCTAssertEqual(payload.mutationItems[0].detail, "created task")
        XCTAssertEqual(payload.mutationItems[1].error, "state not found")
    }

    func testSingleMutationDecodesMutationResult() throws {
        let output = try json(#"""
        {"ok": true, "action": "updated", "resourceType": "project", "id": "proj-1", "name": "Website"}
        """#)

        let payload = try XCTUnwrap(BoardToolPayload(toolName: "board_update_project", output: output))

        XCTAssertFalse(payload.isBatchMutation)
        XCTAssertEqual(payload.mutationItems.count, 1)
        XCTAssertEqual(payload.mutationItems[0].name, "Website")
        XCTAssertEqual(payload.mutationItems[0].detail, "updated project")
    }

    func testStringEncodedOutputDecodesLikeAnObject() throws {
        let output = JSONValue.string(#"{"id":"proj-1","name":"Website","states":[]}"#)

        let payload = try XCTUnwrap(BoardToolPayload(toolName: "board_get_project", output: output))

        XCTAssertEqual(payload.projects.first?.name, "Website")
    }

    func testUnknownToolAndMalformedOutputFailToDecode() throws {
        let output = try json(#"{"id":"x"}"#)
        XCTAssertNil(BoardToolPayload(toolName: "board_delete_task", output: output))
        XCTAssertNil(BoardToolPayload(toolName: "board_search_tasks", output: output))
        XCTAssertNil(BoardToolPayload(toolName: "board_search_projects", output: nil))
    }
}
