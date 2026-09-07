import { useMutation, useQueryClient } from '@tanstack/react-query';
import { MutationKeys, QueryKeys, dataService } from 'librechat-data-provider';
import type { TApproveUserResponse } from 'librechat-data-provider';
import type { UseMutationResult } from '@tanstack/react-query';

export function useApproveUserMutation(): UseMutationResult<
  TApproveUserResponse,
  Error,
  string,
  unknown
> {
  const queryClient = useQueryClient();

  return useMutation<TApproveUserResponse, Error, string>(
    [MutationKeys.approveUser],
    (userId) => dataService.approveAdminUser(userId),
    {
      onSuccess: () => queryClient.invalidateQueries([QueryKeys.adminPendingUsers]),
    },
  );
}
