import { NextApiRequest, NextApiResponse } from 'next';
import { createRouter, NextHandler } from 'next-connect';
import { UserController } from '../controllers/user.controller';

const router = createRouter<NextApiRequest, NextApiResponse>();
const userController = new UserController();

// Middleware function type
type MiddlewareFunction = (
  req: NextApiRequest,
  res: NextApiResponse,
  next: NextHandler
) => Promise<void> | void;

// Auth middleware for routes
const authMiddleware: MiddlewareFunction = (req, res, next) => {
  const token = req.headers.authorization?.split(' ')[1];
  
  if (!token) {
    return res.status(401).json({ 
      success: false, 
      error: 'Authentication required' 
    });
  }

  return next();
};

// Apply auth middleware to all routes
router.use(authMiddleware);

// Route handlers
router.get(async (req, res) => {
  await userController.getUsers(req, res);
});

router.get('/:id', async (req, res) => {
  await userController.getUserById(req, res);
});

router.post(async (req, res) => {
  await userController.createUser(req, res);
});

router.put('/:id', async (req, res) => {
  await userController.updateUser(req, res);
});

router.delete('/:id', async (req, res) => {
  await userController.deleteUser(req, res);
});

export default router; 