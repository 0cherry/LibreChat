import { useQuery } from '@tanstack/react-query';
import { QueryKeys, dataService } from 'librechat-data-provider';
import type { TAdminPendingUsersResponse } from 'librechat-data-provider';
import type { QueryObserverResult } from '@tanstack/react-query';

export function usePendingUsersQuery(
  enabled: boolean,
): QueryObserverResult<TAdminPendingUsersResponse> {
  return useQuery<TAdminPendingUsersResponse>(
    [QueryKeys.adminPendingUsers],
    () => dataService.getAdminPendingUsers(),
    {
      enabled,
      retry: false,
      refetchOnWindowFocus: true,
    },
  );
}
