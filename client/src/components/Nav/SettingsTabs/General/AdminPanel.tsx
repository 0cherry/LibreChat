import { useState } from 'react';
import { SystemRoles } from 'librechat-data-provider';
import { ExternalLink, RefreshCw } from 'lucide-react';
import { Alert, Label, Button, Spinner } from '@librechat/client';
import { usePendingUsersQuery, useApproveUserMutation, useGetStartupConfig } from '~/data-provider';
import { useAuthContext, useLocalize } from '~/hooks';

export default function AdminPanel() {
  const localize = useLocalize();
  const { user } = useAuthContext();
  const { data: startupConfig } = useGetStartupConfig();
  const adminPanelURL = startupConfig?.adminPanelURL ?? '';
  const isAdmin = user?.role === SystemRoles.ADMIN;
  const pendingUsers = usePendingUsersQuery(isAdmin);
  const approveUser = useApproveUserMutation();
  const [approvingUserId, setApprovingUserId] = useState<string>();

  if (!adminPanelURL && !isAdmin) {
    return null;
  }

  return (
    <div className="space-y-5">
      {adminPanelURL && (
        <div className="flex items-center justify-between gap-3">
          <Label id="admin-panel-label">{localize('com_ui_admin_panel')}</Label>
          <Button asChild variant="outline" aria-labelledby="admin-panel-label">
            <a href={adminPanelURL} target="_blank" rel="noopener noreferrer">
              {localize('com_ui_open_var', { 0: localize('com_ui_admin_panel') })}
              <ExternalLink className="size-4" aria-hidden="true" />
            </a>
          </Button>
        </div>
      )}

      {isAdmin && (
        <section aria-labelledby="registration-approvals-label" className="space-y-3">
          <div className="flex items-start justify-between gap-3">
            <div>
              <Label id="registration-approvals-label">
                {localize('com_ui_registration_approvals')}
              </Label>
              <p className="mt-1 text-sm text-text-secondary">
                {localize('com_ui_registration_approvals_description')}
              </p>
            </div>
            <Button
              variant="outline"
              size="sm"
              disabled={pendingUsers.isFetching}
              onClick={() => pendingUsers.refetch()}
              aria-label={localize('com_ui_refresh')}
            >
              <RefreshCw
                className={`size-4 ${pendingUsers.isFetching ? 'animate-spin' : ''}`}
                aria-hidden="true"
              />
              {localize('com_ui_refresh')}
            </Button>
          </div>

          {(pendingUsers.isError || approveUser.isError) && (
            <Alert variant="error" icon={false}>
              {localize('com_ui_registration_approvals_error')}
            </Alert>
          )}

          {pendingUsers.isLoading ? (
            <div className="flex justify-center py-6" aria-label={localize('com_ui_loading')}>
              <Spinner />
            </div>
          ) : pendingUsers.data?.users.length ? (
            <ul className="divide-y divide-border-light overflow-hidden rounded-xl border border-border-light">
              {pendingUsers.data.users.map((pendingUser) => {
                const isApproving = approveUser.isLoading && approvingUserId === pendingUser.id;
                return (
                  <li
                    key={pendingUser.id}
                    className="flex flex-col justify-between gap-3 px-4 py-3 sm:flex-row sm:items-center"
                  >
                    <div className="min-w-0">
                      <p className="truncate font-medium text-text-primary">{pendingUser.name}</p>
                      <p className="truncate text-sm text-text-secondary">{pendingUser.email}</p>
                      {pendingUser.createdAt && (
                        <p className="mt-1 text-xs text-text-tertiary">
                          {localize('com_ui_registration_requested_at', {
                            0: new Date(pendingUser.createdAt).toLocaleString(),
                          })}
                        </p>
                      )}
                    </div>
                    <Button
                      variant="submit"
                      size="sm"
                      disabled={approveUser.isLoading}
                      onClick={() => {
                        setApprovingUserId(pendingUser.id);
                        approveUser.mutate(pendingUser.id, {
                          onSettled: () => setApprovingUserId(undefined),
                        });
                      }}
                    >
                      {isApproving ? <Spinner /> : localize('com_ui_approve')}
                    </Button>
                  </li>
                );
              })}
            </ul>
          ) : (
            <p className="rounded-xl border border-border-light px-4 py-5 text-center text-sm text-text-secondary">
              {localize('com_ui_registration_approvals_empty')}
            </p>
          )}
        </section>
      )}
    </div>
  );
}
