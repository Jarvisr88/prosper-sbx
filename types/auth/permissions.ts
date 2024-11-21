export enum Permission {
  MANAGE_SETTINGS = 'manage:settings',
  MANAGE_USERS = 'manage:users',
  VIEW_AUDIT_LOGS = 'view:audit_logs',
  MANAGE_ROLES = 'manage:roles',
  READ_USER = 'read:user',
  UPDATE_USER = 'update:user',
  VIEW_RESOURCES = 'view:resources',
  VIEW_REPORTS = 'view:reports',
  CREATE_REPORTS = 'create:reports',
  EXPORT_DATA = 'export:data'
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
    Permission.EXPORT_DATA
  ],
  user: [
    Permission.READ_USER,
    Permission.VIEW_RESOURCES,
    Permission.VIEW_REPORTS
  ],
  developer: [
    Permission.READ_USER,
    Permission.VIEW_RESOURCES,
    Permission.VIEW_REPORTS,
    Permission.CREATE_REPORTS
  ],
  analyst: [
    Permission.READ_USER,
    Permission.VIEW_RESOURCES,
    Permission.VIEW_REPORTS,
    Permission.CREATE_REPORTS,
    Permission.EXPORT_DATA
  ]
} 