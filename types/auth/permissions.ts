export enum Permission {
  READ_USER = "read:user",
  CREATE_USER = "create:user",
  UPDATE_USER = "update:user",
  DELETE_USER = "delete:user",
  MANAGE_USERS = "manage:users",
  VIEW_RESOURCES = "view:resources",
  MANAGE_RESOURCES = "manage:resources",
  VIEW_REPORTS = "view:reports",
  CREATE_REPORTS = "create:reports",
  EXPORT_DATA = "export:data",
  MANAGE_ROLES = "manage:roles",
  MANAGE_SETTINGS = "manage:settings",
  MANAGE_CONFIG = "manage:config",
  MANAGE_HEALTH = "manage:health",
  MANAGE_METRICS = "manage:metrics",
  VIEW_AUDIT_LOGS = "view:audit_logs",
  MANAGE_NOTIFICATIONS = "manage:notifications",
  MANAGE_SECURITY = "manage:security",
  MANAGE_WORKFLOWS = "manage:workflows",
  ADMIN = "admin",
}

export interface RolePermissions {
  admin: Permission[];
  manager: Permission[];
  user: Permission[];
  developer: Permission[];
  analyst: Permission[];
}

export const DEFAULT_ROLE_PERMISSIONS: RolePermissions = {
  admin: Object.values(Permission),
  manager: [
    Permission.READ_USER,
    Permission.UPDATE_USER,
    Permission.VIEW_RESOURCES,
    Permission.VIEW_REPORTS,
    Permission.CREATE_REPORTS,
    Permission.EXPORT_DATA,
    Permission.VIEW_AUDIT_LOGS,
    Permission.MANAGE_SETTINGS,
    Permission.MANAGE_HEALTH,
  ],
  user: [
    Permission.READ_USER,
    Permission.VIEW_RESOURCES,
    Permission.VIEW_REPORTS,
  ],
  developer: [
    Permission.READ_USER,
    Permission.VIEW_RESOURCES,
    Permission.VIEW_REPORTS,
    Permission.CREATE_REPORTS,
    Permission.VIEW_AUDIT_LOGS,
  ],
  analyst: [
    Permission.READ_USER,
    Permission.VIEW_RESOURCES,
    Permission.VIEW_REPORTS,
    Permission.CREATE_REPORTS,
    Permission.EXPORT_DATA,
  ],
};
