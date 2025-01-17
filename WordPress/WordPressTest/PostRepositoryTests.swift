import XCTest

@testable import WordPress

class PostRepositoryTests: CoreDataTestCase {

    private var remoteMock: PostServiceRESTMock!
    private var repository: PostRepository!
    private var blogID: TaggedManagedObjectID<Blog>!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let accountService = AccountService(coreDataStack: contextManager)
        let accountID = accountService.createOrUpdateAccount(withUsername: "username", authToken: "token")
        try accountService.setDefaultWordPressComAccount(XCTUnwrap(mainContext.existingObject(with: accountID) as? WPAccount))

        let blog = try BlogBuilder(mainContext).withAccount(id: accountID).build()

        contextManager.saveContextAndWait(mainContext)

        blogID = .init(blog)
        remoteMock = PostServiceRESTMock()
        let remoteFactory = PostServiceRemoteFactoryMock()
        remoteFactory.remoteToReturn = remoteMock
        repository = PostRepository(coreDataStack: contextManager, remoteFactory: remoteFactory)
    }

    func testGetPost() async throws {
        let post = RemotePost(siteID: 1, status: "publish", title: "Post: Test", content: "This is a test post")
        post?.type = "post"
        remoteMock.remotePostToReturnOnGetPostWithID = post
        let postID = try await repository.getPost(withID: 1, from: blogID)
        let isPage = try await contextManager.performQuery { try $0.existingObject(with: postID) is Page }
        let title = try await contextManager.performQuery { try $0.existingObject(with: postID).postTitle }
        let content = try await contextManager.performQuery { try $0.existingObject(with: postID).content }
        XCTAssertFalse(isPage)
        XCTAssertEqual(title, "Post: Test")
        XCTAssertEqual(content, "This is a test post")
    }

    func testGetPage() async throws {
        let post = RemotePost(siteID: 1, status: "publish", title: "Post: Test", content: "This is a test post")
        post?.type = "page"
        remoteMock.remotePostToReturnOnGetPostWithID = post
        let postID = try await repository.getPost(withID: 1, from: blogID)
        let isPage = try await contextManager.performQuery { try $0.existingObject(with: postID) is Page }
        let title = try await contextManager.performQuery { try $0.existingObject(with: postID).postTitle }
        let content = try await contextManager.performQuery { try $0.existingObject(with: postID).content }
        XCTAssertTrue(isPage)
        XCTAssertEqual(title, "Post: Test")
        XCTAssertEqual(content, "This is a test post")
    }

    func testDeletePost() async throws {
        let postID = try await contextManager.performAndSave { context in
            let post = PostBuilder(context).withRemote().with(title: "Post: Test").build()
            return TaggedManagedObjectID(post)
        }

        remoteMock.deletePostResult = .success(())
        try await repository.delete(postID)

        let isPostDeleted = await contextManager.performQuery { context in
            (try? context.existingObject(with: postID)) == nil
        }
        XCTAssertTrue(isPostDeleted)
    }

    func testDeletePostWithRemoteFailure() async throws {
        let postID = try await contextManager.performAndSave { context in
            let post = PostBuilder(context).withRemote().with(title: "Post: Test").build()
            return TaggedManagedObjectID(post)
        }

        remoteMock.deletePostResult = .failure(NSError.testInstance())
        do {
            try await repository.delete(postID)
            XCTFail("The deletion should fail because of an API failure")
        } catch {
            // Do nothing
        }

        let isPostDeleted = await contextManager.performQuery { context in
            (try? context.existingObject(with: postID)) == nil
        }
        XCTAssertTrue(isPostDeleted)
    }

    func testDeleteHistory() async throws {
        let (firstRevision, secondRevision) = try await contextManager.performAndSave { context in
            let first = PostBuilder(context).withRemote().with(title: "Post: Test").build()
            let second = first.createRevision()
            second.postTitle = "Edited"
            return (TaggedManagedObjectID(first), TaggedManagedObjectID(second))
        }

        remoteMock.deletePostResult = .success(())
        try await repository.delete(firstRevision)

        let isPostDeleted = await contextManager.performQuery { context in
            (try? context.existingObject(with: firstRevision)) == nil
              && (try? context.existingObject(with: secondRevision)) == nil
        }
        XCTAssertTrue(isPostDeleted)
    }

    func testDeleteLatest() async throws {
        let (firstRevision, secondRevision) = try await contextManager.performAndSave { context in
            let first = PostBuilder(context).withRemote().with(title: "Post: Test").build()
            let second = first.createRevision()
            second.postTitle = "Edited"
            return (TaggedManagedObjectID(first), TaggedManagedObjectID(second))
        }

        remoteMock.deletePostResult = .success(())
        try await repository.delete(secondRevision)

        let isPostDeleted = await contextManager.performQuery { context in
            (try? context.existingObject(with: firstRevision)) == nil
              && (try? context.existingObject(with: secondRevision)) == nil
        }
        XCTAssertTrue(isPostDeleted)
    }

    func testTrashPost() async throws {
        let postID = try await contextManager.performAndSave { context in
            let post = PostBuilder(context).withRemote().with(title: "Post: Test").build()
            return TaggedManagedObjectID(post)
        }

        // No API call should be made, because the post is a local post
        let remotePost = RemotePost(siteID: 1, status: "trash", title: "Post: Test", content: "New content")!
        remotePost.type = "post"
        remoteMock.trashPostResult = .success(remotePost)
        try await repository.trash(postID)

        let content = try await contextManager.performQuery { context in
            (try context.existingObject(with: postID)).content
        }
        XCTAssertEqual(content, "New content")
    }

    func testTrashLocalPost() async throws {
        let postID = try await contextManager.performAndSave { context in
            let post = PostBuilder(context).with(title: "Post: Test").build()
            return TaggedManagedObjectID(post)
        }

        // No API call should be made, because the post is a local post
        remoteMock.trashPostResult = .failure(NSError.testInstance())
        try await repository.trash(postID)

        let status = try await contextManager.performQuery { context in
            (try context.existingObject(with: postID)).status
        }
        XCTAssertEqual(status, .trash)
    }

    func testTrashTrashedPost() async throws {
        let postID = try await contextManager.performAndSave { context in
            let post = PostBuilder(context).with(status: .trash).with(title: "Post: Test").build()
            return TaggedManagedObjectID(post)
        }

        // No API call should be made, because the post is a local post
        remoteMock.trashPostResult = .failure(NSError.testInstance())
        remoteMock.deletePostResult = .failure(NSError.testInstance())
        try await repository.trash(postID)

        let isPostDeleted = await contextManager.performQuery { context in
            (try? context.existingObject(with: postID)) == nil
        }
        XCTAssertTrue(isPostDeleted)
    }

    func testRestorePost() async throws {
        let postID = try await contextManager.performAndSave { context in
            let post = PostBuilder(context).withRemote().with(status: .trash).with(title: "Post: Test").build()
            return TaggedManagedObjectID(post)
        }

        let remotePost = RemotePost(siteID: 1, status: "draft", title: "Post: Test", content: "New content")!
        remotePost.type = "post"
        remoteMock.restorePostResult = .success(remotePost)
        try await repository.restore(postID, to: .publish)

        // The restored post should match the post returned by WordPress API.
        let (status, content) = try await contextManager.performQuery { context in
            let post = try context.existingObject(with: postID)
            return (post.status, post.content)
        }
        XCTAssertEqual(status, .draft)
        XCTAssertEqual(content, "New content")
    }

    func testRestorePostFailure() async throws {
        let postID = try await contextManager.performAndSave { context in
            let post = PostBuilder(context).withRemote().with(status: .trash).with(title: "Post: Test").build()
            return TaggedManagedObjectID(post)
        }

        remoteMock.restorePostResult = .failure(NSError.testInstance())

        do {
            try await repository.restore(postID, to: .publish)
            XCTFail("The restore call should throw an error")
        } catch {
            let status = try await contextManager.performQuery { context in
                let post = try context.existingObject(with: postID)
                return post.status
            }
            XCTAssertEqual(status, .trash)
        }
    }

}

// These mock classes are copied from PostServiceWPComTests. We can't simply remove the `private` in the original class
// definition, because Xcode would complian about 'WordPress' module not found.

private class PostServiceRemoteFactoryMock: PostServiceRemoteFactory {
    var remoteToReturn: PostServiceRemote?

    override func forBlog(_ blog: Blog) -> PostServiceRemote? {
        return remoteToReturn
    }

    override func restRemoteFor(siteID: NSNumber, context: NSManagedObjectContext) -> PostServiceRemoteREST? {
        return remoteToReturn as? PostServiceRemoteREST
    }
}

private class PostServiceRESTMock: PostServiceRemoteREST {
    enum StubbedBehavior {
        case success(RemotePost?)
        case fail
    }

    var remotePostToReturnOnGetPostWithID: RemotePost?
    var remotePostsToReturnOnSyncPostsOfType = [RemotePost]()
    var remotePostToReturnOnUpdatePost: RemotePost?
    var remotePostToReturnOnCreatePost: RemotePost?

    var autoSaveStubbedBehavior = StubbedBehavior.success(nil)

    // related to fetching likes
    var fetchLikesShouldSucceed: Bool = true
    var remoteUsersToReturnOnGetLikes = [RemoteLikeUser]()
    var totalLikes: NSNumber = 1

    var deletePostResult: Result<Void, Error> = .success(())
    var trashPostResult: Result<RemotePost, Error> = .failure(NSError.testInstance())
    var restorePostResult: Result<RemotePost, Error> = .failure(NSError.testInstance())

    private(set) var invocationsCountOfCreatePost = 0
    private(set) var invocationsCountOfAutoSave = 0
    private(set) var invocationsCountOfUpdate = 0

    override func getPostWithID(_ postID: NSNumber!, success: ((RemotePost?) -> Void)!, failure: ((Error?) -> Void)!) {
        success(self.remotePostToReturnOnGetPostWithID)
    }

    override func getPostsOfType(_ postType: String!, options: [AnyHashable: Any]! = [:], success: (([RemotePost]?) -> Void)!, failure: ((Error?) -> Void)!) {
        success(self.remotePostsToReturnOnSyncPostsOfType)
    }

    override func update(_ post: RemotePost!, success: ((RemotePost?) -> Void)!, failure: ((Error?) -> Void)!) {
        self.invocationsCountOfUpdate += 1
        success(self.remotePostToReturnOnUpdatePost)
    }

    override func createPost(_ post: RemotePost!, success: ((RemotePost?) -> Void)!, failure: ((Error?) -> Void)!) {
        self.invocationsCountOfCreatePost += 1
        success(self.remotePostToReturnOnCreatePost)
    }

    override func trashPost(_ post: RemotePost!, success: ((RemotePost?) -> Void)!, failure: ((Error?) -> Void)!) {
        switch self.trashPostResult {
        case let .failure(error):
            failure(error)
        case let .success(remotePost):
            success(remotePost)
        }
    }

    override func restore(_ post: RemotePost!, success: ((RemotePost?) -> Void)!, failure: ((Error?) -> Void)!) {
        switch self.restorePostResult {
        case let .failure(error):
            failure(error)
        case let .success(remotePost):
            success(remotePost)
        }
    }

    override func autoSave(_ post: RemotePost, success: ((RemotePost?, String?) -> Void)!, failure: ((Error?) -> Void)!) {
        self.invocationsCountOfAutoSave += 1

        switch self.autoSaveStubbedBehavior {
        case .fail:
            failure(nil)
        case .success(let remotePost):
            success(remotePost, nil)
        }
    }

    override func getLikesForPostID(_ postID: NSNumber,
                                    count: NSNumber,
                                    before: String?,
                                    excludeUserIDs: [NSNumber]?,
                                    success: (([RemoteLikeUser], NSNumber) -> Void)!,
                                    failure: ((Error?) -> Void)!) {
        if self.fetchLikesShouldSucceed {
            success(self.remoteUsersToReturnOnGetLikes, self.totalLikes)
        } else {
            failure(nil)
        }
    }

    override func delete(_ post: RemotePost!, success: (() -> Void)!, failure: ((Error?) -> Void)!) {
        switch deletePostResult {
        case let .failure(error):
            failure(error)
        case .success:
            success()
        }
    }
}
