import { useSession, signOut } from 'next-auth/react';
import Image from 'next/image';

export default function UserMenu() {
  const { data: session } = useSession();

  if (!session) return null;

  return (
    <div className="flex items-center gap-4">
      <div className="text-sm">
        <div className="font-medium">{session.user.name}</div>
        <div className="text-gray-500">{session.user.email}</div>
      </div>
      {session.user.image && (
        <Image
          src={session.user.image}
          alt="Profile"
          width={32}
          height={32}
          className="rounded-full"
        />
      )}
      <button
        onClick={() => signOut()}
        className="rounded-md bg-red-600 px-4 py-2 text-sm text-white hover:bg-red-700"
      >
        Sign Out
      </button>
    </div>
  );
} 