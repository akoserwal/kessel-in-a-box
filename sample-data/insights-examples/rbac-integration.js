#!/usr/bin/env node

/**
 * Insights RBAC Integration with Kessel
 *
 * Demonstrates how to integrate traditional RBAC service with Kessel ReBAC.
 *
 * Use cases covered:
 * - Check if user can access a workspace
 * - Check if user can manage an application
 * - List all workspaces a user can view
 * - Grant/revoke permissions
 * - Role-based access with group inheritance
 */

const { v1 } = require("@authzed/authzed-node");

// SpiceDB client configuration
const client = v1.NewClient(
  process.env.SPICEDB_TOKEN || "testtesttesttest",
  process.env.SPICEDB_ENDPOINT || "localhost:50051",
  v1.ClientSecurity.INSECURE_PLAINTEXT_CREDENTIALS
);

// ============================================================================
// Permission Checking Functions
// ============================================================================

/**
 * Check if a user can perform an action on a workspace
 */
async function canUserAccessWorkspace(userId, workspaceId, permission = 'view') {
  console.log(`\n🔍 Checking: Can ${userId} ${permission} ${workspaceId}?`);

  const request = v1.CheckPermissionRequest.create({
    resource: v1.ObjectReference.create({
      objectType: "workspace",
      objectId: workspaceId,
    }),
    permission: permission,
    subject: v1.SubjectReference.create({
      object: v1.ObjectReference.create({
        objectType: "user",
        objectId: userId,
      }),
    }),
  });

  try {
    const response = await client.checkPermission(request);
    const allowed = response.permissionship === v1.CheckPermissionResponse_Permissionship.HAS_PERMISSION;

    console.log(`   Result: ${allowed ? '✅ ALLOWED' : '❌ DENIED'}`);
    return allowed;
  } catch (error) {
    console.error(`   Error: ${error.message}`);
    return false;
  }
}

/**
 * Check if a user can manage an application
 */
async function canUserManageApplication(userId, applicationId) {
  console.log(`\n🔍 Checking: Can ${userId} manage application:${applicationId}?`);

  const request = v1.CheckPermissionRequest.create({
    resource: v1.ObjectReference.create({
      objectType: "application",
      objectId: applicationId,
    }),
    permission: "manage",
    subject: v1.SubjectReference.create({
      object: v1.ObjectReference.create({
        objectType: "user",
        objectId: userId,
      }),
    }),
  });

  try {
    const response = await client.checkPermission(request);
    const allowed = response.permissionship === v1.CheckPermissionResponse_Permissionship.HAS_PERMISSION;

    console.log(`   Result: ${allowed ? '✅ ALLOWED' : '❌ DENIED'}`);
    return allowed;
  } catch (error) {
    console.error(`   Error: ${error.message}`);
    return false;
  }
}

/**
 * Check organization admin status
 */
async function isOrgAdmin(userId, orgId) {
  console.log(`\n🔍 Checking: Is ${userId} admin of ${orgId}?`);

  const request = v1.CheckPermissionRequest.create({
    resource: v1.ObjectReference.create({
      objectType: "organization",
      objectId: orgId,
    }),
    permission: "manage",
    subject: v1.SubjectReference.create({
      object: v1.ObjectReference.create({
        objectType: "user",
        objectId: userId,
      }),
    }),
  });

  try {
    const response = await client.checkPermission(request);
    const allowed = response.permissionship === v1.CheckPermissionResponse_Permissionship.HAS_PERMISSION;

    console.log(`   Result: ${allowed ? '✅ IS ADMIN' : '❌ NOT ADMIN'}`);
    return allowed;
  } catch (error) {
    console.error(`   Error: ${error.message}`);
    return false;
  }
}

// ============================================================================
// Relationship Management Functions
// ============================================================================

/**
 * Grant a user access to a workspace
 */
async function grantWorkspaceAccess(userId, workspaceId, role = 'viewer') {
  console.log(`\n✍️  Granting ${userId} ${role} access to ${workspaceId}`);

  const request = v1.WriteRelationshipsRequest.create({
    updates: [
      v1.RelationshipUpdate.create({
        operation: v1.RelationshipUpdate_Operation.TOUCH,
        relationship: v1.Relationship.create({
          resource: v1.ObjectReference.create({
            objectType: "workspace",
            objectId: workspaceId,
          }),
          relation: role,
          subject: v1.SubjectReference.create({
            object: v1.ObjectReference.create({
              objectType: "user",
              objectId: userId,
            }),
          }),
        }),
      }),
    ],
  });

  try {
    const response = await client.writeRelationships(request);
    console.log(`   ✅ Access granted at token: ${response.writtenAt.token}`);
    return response.writtenAt;
  } catch (error) {
    console.error(`   ❌ Error: ${error.message}`);
    throw error;
  }
}

/**
 * Revoke a user's access to a workspace
 */
async function revokeWorkspaceAccess(userId, workspaceId, role = 'viewer') {
  console.log(`\n🗑️  Revoking ${userId} ${role} access from ${workspaceId}`);

  const request = v1.WriteRelationshipsRequest.create({
    updates: [
      v1.RelationshipUpdate.create({
        operation: v1.RelationshipUpdate_Operation.DELETE,
        relationship: v1.Relationship.create({
          resource: v1.ObjectReference.create({
            objectType: "workspace",
            objectId: workspaceId,
          }),
          relation: role,
          subject: v1.SubjectReference.create({
            object: v1.ObjectReference.create({
              objectType: "user",
              objectId: userId,
            }),
          }),
        }),
      }),
    ],
  });

  try {
    const response = await client.writeRelationships(request);
    console.log(`   ✅ Access revoked at token: ${response.writtenAt.token}`);
    return response.writtenAt;
  } catch (error) {
    console.error(`   ❌ Error: ${error.message}`);
    throw error;
  }
}

/**
 * Add user to a group
 */
async function addUserToGroup(userId, groupUuid) {
  console.log(`\n👥 Adding ${userId} to group:${groupUuid}`);

  const request = v1.WriteRelationshipsRequest.create({
    updates: [
      v1.RelationshipUpdate.create({
        operation: v1.RelationshipUpdate_Operation.TOUCH,
        relationship: v1.Relationship.create({
          resource: v1.ObjectReference.create({
            objectType: "group",
            objectId: groupUuid,
          }),
          relation: "member",
          subject: v1.SubjectReference.create({
            object: v1.ObjectReference.create({
              objectType: "user",
              objectId: userId,
            }),
          }),
        }),
      }),
    ],
  });

  try {
    const response = await client.writeRelationships(request);
    console.log(`   ✅ User added to group at token: ${response.writtenAt.token}`);
    return response.writtenAt;
  } catch (error) {
    console.error(`   ❌ Error: ${error.message}`);
    throw error;
  }
}

// ============================================================================
// Lookup/Discovery Functions
// ============================================================================

/**
 * List all workspaces a user can view
 */
async function listUserWorkspaces(userId) {
  console.log(`\n📋 Listing workspaces viewable by ${userId}...`);

  const request = v1.LookupResourcesRequest.create({
    resourceObjectType: "workspace",
    permission: "view",
    subject: v1.SubjectReference.create({
      object: v1.ObjectReference.create({
        objectType: "user",
        objectId: userId,
      }),
    }),
  });

  try {
    const workspaces = [];
    for await (const response of client.lookupResources(request)) {
      workspaces.push(response.resourceObjectId);
    }

    console.log(`   Found ${workspaces.length} workspaces:`);
    workspaces.forEach(ws => console.log(`     - ${ws}`));
    return workspaces;
  } catch (error) {
    console.error(`   Error: ${error.message}`);
    return [];
  }
}

/**
 * List all applications a user can access
 */
async function listUserApplications(userId) {
  console.log(`\n📋 Listing applications accessible to ${userId}...`);

  const request = v1.LookupResourcesRequest.create({
    resourceObjectType: "application",
    permission: "access",
    subject: v1.SubjectReference.create({
      object: v1.ObjectReference.create({
        objectType: "user",
        objectId: userId,
      }),
    }),
  });

  try {
    const applications = [];
    for await (const response of client.lookupResources(request)) {
      applications.push(response.resourceObjectId);
    }

    console.log(`   Found ${applications.length} applications:`);
    applications.forEach(app => console.log(`     - ${app}`));
    return applications;
  } catch (error) {
    console.error(`   Error: ${error.message}`);
    return [];
  }
}

/**
 * List all users who can view a workspace
 */
async function listWorkspaceViewers(workspaceId) {
  console.log(`\n📋 Listing users who can view ${workspaceId}...`);

  const request = v1.LookupSubjectsRequest.create({
    resource: v1.ObjectReference.create({
      objectType: "workspace",
      objectId: workspaceId,
    }),
    permission: "view",
    subjectObjectType: "user",
  });

  try {
    const users = [];
    for await (const response of client.lookupSubjects(request)) {
      users.push(response.subject.object.objectId);
    }

    console.log(`   Found ${users.length} viewers:`);
    users.forEach(user => console.log(`     - ${user}`));
    return users;
  } catch (error) {
    console.error(`   Error: ${error.message}`);
    return [];
  }
}

// ============================================================================
// Demo Scenarios
// ============================================================================

async function runDemoScenarios() {
  console.log("╔═══════════════════════════════════════════════════════════╗");
  console.log("║   Insights RBAC → Kessel Integration Demo                ║");
  console.log("╚═══════════════════════════════════════════════════════════╝");

  // Scenario 1: Organization Admin Checks
  console.log("\n━━━ Scenario 1: Organization Admin Checks ━━━");
  await isOrgAdmin("alice", "acme-corp");  // Should be ALLOWED
  await isOrgAdmin("bob", "acme-corp");    // Should be DENIED

  // Scenario 2: Workspace Access Checks
  console.log("\n━━━ Scenario 2: Workspace Access Checks ━━━");
  await canUserAccessWorkspace("alice", "production", "manage");  // Owner
  await canUserAccessWorkspace("bob", "production", "edit");      // Via sre-team
  await canUserAccessWorkspace("carol", "production", "view");    // Via developers
  await canUserAccessWorkspace("eve", "production", "view");      // Should be DENIED

  // Scenario 3: Application Access Checks
  console.log("\n━━━ Scenario 3: Application Access Checks ━━━");
  await canUserManageApplication("alice", "advisor");  // Owner
  await canUserManageApplication("bob", "advisor");    // Should be DENIED

  // Scenario 4: List User Resources
  console.log("\n━━━ Scenario 4: List User Resources ━━━");
  await listUserWorkspaces("bob");
  await listUserApplications("carol");

  // Scenario 5: Grant/Revoke Access
  console.log("\n━━━ Scenario 5: Grant/Revoke Access ━━━");

  // Grant eve viewer access to staging workspace
  await grantWorkspaceAccess("eve", "staging", "viewer");

  // Verify access was granted
  await canUserAccessWorkspace("eve", "staging", "view");  // Should now be ALLOWED

  // Revoke access
  await revokeWorkspaceAccess("eve", "staging", "viewer");

  // Verify access was revoked
  await canUserAccessWorkspace("eve", "staging", "view");  // Should be DENIED again

  // Scenario 6: Group Management
  console.log("\n━━━ Scenario 6: Group Management ━━━");

  // Add eve to developers group
  await addUserToGroup("eve", "550e8400-e29b-41d4-a716-446655440003");

  // Check if eve now has access through group membership
  await canUserAccessWorkspace("eve", "production", "view");  // Should be ALLOWED via developers group

  // Scenario 7: Workspace Viewers Lookup
  console.log("\n━━━ Scenario 7: Workspace Viewers Lookup ━━━");
  await listWorkspaceViewers("production");

  console.log("\n╔═══════════════════════════════════════════════════════════╗");
  console.log("║   Demo Completed Successfully!                            ║");
  console.log("╚═══════════════════════════════════════════════════════════╝\n");
}

// Run the demo
if (require.main === module) {
  runDemoScenarios()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("Demo failed:", error);
      process.exit(1);
    });
}

module.exports = {
  canUserAccessWorkspace,
  canUserManageApplication,
  isOrgAdmin,
  grantWorkspaceAccess,
  revokeWorkspaceAccess,
  addUserToGroup,
  listUserWorkspaces,
  listUserApplications,
  listWorkspaceViewers,
};
