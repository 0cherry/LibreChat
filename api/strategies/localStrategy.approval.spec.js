const mockComparePassword = jest.fn();
const mockFindUser = jest.fn();

jest.mock('@librechat/data-schemas', () => ({
  logger: {
    error: jest.fn(),
    warn: jest.fn(),
    info: jest.fn(),
  },
}));

jest.mock('@librechat/api', () => ({
  isEnabled: jest.fn(() => true),
  checkEmailConfig: jest.fn(() => false),
  comparePassword: (...args) => mockComparePassword(...args),
}));

jest.mock('~/models', () => ({
  findUser: (...args) => mockFindUser(...args),
  updateUser: jest.fn(),
}));

const createLocalStrategy = require('./localStrategy');

describe('localStrategy registration approval', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockComparePassword.mockResolvedValue(true);
    mockFindUser.mockResolvedValue({
      _id: 'user-id',
      email: 'pending@example.com',
      password: 'hashed-password',
      isApproved: false,
      emailVerified: true,
      createdAt: new Date(),
    });
  });

  it('blocks a pending account after validating its password', async () => {
    const strategy = createLocalStrategy();
    const done = jest.fn();
    const req = {
      body: { email: 'pending@example.com', password: 'Password123!' },
      ip: '127.0.0.1',
    };

    await strategy._verify(req, 'pending@example.com', 'Password123!', done);

    expect(mockComparePassword).toHaveBeenCalledTimes(1);
    expect(done).toHaveBeenCalledWith(null, false, {
      message: 'Account pending administrator approval.',
      status: 423,
    });
  });
});
