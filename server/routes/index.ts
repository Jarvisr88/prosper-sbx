import { NextApiRequest, NextApiResponse } from 'next';
import { createRouter } from 'next-connect';
import userRoutes from './user.routes';

const router = createRouter<NextApiRequest, NextApiResponse>();

// Base routes
router.use('/api/users', userRoutes);

export default router;