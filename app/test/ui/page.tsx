'use client'

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Calendar } from "@/components/ui/calendar"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { toast } from "@/hooks/use-toast"
import { Checkbox } from "@/components/ui/checkbox"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { Switch } from "@/components/ui/switch"
import { Slider } from "@/components/ui/slider"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Progress } from "@/components/ui/progress"
import { HoverCard, HoverCardContent, HoverCardTrigger } from "@/components/ui/hover-card"
import { NavigationMenu, NavigationMenuContent, NavigationMenuItem, NavigationMenuLink, NavigationMenuList, NavigationMenuTrigger } from "@/components/ui/navigation-menu"
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet"

export default function UITestPage() {
  const [date, setDate] = useState<Date | undefined>(new Date())
  const [progress, setProgress] = useState(0)

  // Simulate progress
  useState(() => {
    const timer = setTimeout(() => setProgress(66), 500)
    return () => clearTimeout(timer)
  })

  return (
    <div className="min-h-screen bg-background">
      {/* Navigation */}
      <nav className="border-b">
        <NavigationMenu className="mx-auto max-w-screen-xl px-4">
          <NavigationMenuList>
            <NavigationMenuItem>
              <NavigationMenuTrigger>Components</NavigationMenuTrigger>
              <NavigationMenuContent>
                <div className="grid gap-3 p-4 w-[400px]">
                  <div className="grid grid-cols-2 gap-2">
                    <NavigationMenuLink className="cursor-pointer">Forms</NavigationMenuLink>
                    <NavigationMenuLink className="cursor-pointer">Data Display</NavigationMenuLink>
                    <NavigationMenuLink className="cursor-pointer">Feedback</NavigationMenuLink>
                    <NavigationMenuLink className="cursor-pointer">Navigation</NavigationMenuLink>
                  </div>
                </div>
              </NavigationMenuContent>
            </NavigationMenuItem>
          </NavigationMenuList>
        </NavigationMenu>
      </nav>

      <main className="container mx-auto py-10 space-y-8">
        <h1 className="text-4xl font-bold">UI Components Test Page</h1>
        
        <Tabs defaultValue="forms" className="w-full">
          <TabsList className="grid w-full grid-cols-4">
            <TabsTrigger value="forms">Forms</TabsTrigger>
            <TabsTrigger value="data">Data Display</TabsTrigger>
            <TabsTrigger value="feedback">Feedback</TabsTrigger>
            <TabsTrigger value="navigation">Navigation</TabsTrigger>
          </TabsList>

          {/* Forms Tab */}
          <TabsContent value="forms">
            <div className="grid gap-6">
              <Card>
                <CardHeader>
                  <CardTitle>Form Components</CardTitle>
                  <CardDescription>Test our form components and their interactions.</CardDescription>
                </CardHeader>
                <CardContent className="space-y-6">
                  {/* Text Inputs */}
                  <div className="grid gap-4">
                    <div className="grid w-full max-w-sm items-center gap-1.5">
                      <Label htmlFor="email">Email</Label>
                      <Input type="email" id="email" placeholder="Email" />
                    </div>
                    <div className="grid w-full max-w-sm items-center gap-1.5">
                      <Label htmlFor="password">Password</Label>
                      <Input type="password" id="password" placeholder="Password" />
                    </div>
                  </div>

                  {/* Checkbox and Switch */}
                  <div className="grid gap-4">
                    <div className="flex items-center space-x-2">
                      <Checkbox id="terms" />
                      <Label htmlFor="terms">Accept terms and conditions</Label>
                    </div>
                    <div className="flex items-center space-x-2">
                      <Switch id="notifications" />
                      <Label htmlFor="notifications">Enable notifications</Label>
                    </div>
                  </div>

                  {/* Radio Group */}
                  <div className="grid gap-2">
                    <Label>Subscription Plan</Label>
                    <RadioGroup defaultValue="standard">
                      <div className="flex items-center space-x-2">
                        <RadioGroupItem value="basic" id="basic" />
                        <Label htmlFor="basic">Basic</Label>
                      </div>
                      <div className="flex items-center space-x-2">
                        <RadioGroupItem value="standard" id="standard" />
                        <Label htmlFor="standard">Standard</Label>
                      </div>
                      <div className="flex items-center space-x-2">
                        <RadioGroupItem value="pro" id="pro" />
                        <Label htmlFor="pro">Pro</Label>
                      </div>
                    </RadioGroup>
                  </div>

                  {/* Select and Slider */}
                  <div className="grid gap-4">
                    <div className="grid w-full max-w-sm items-center gap-1.5">
                      <Label>Theme</Label>
                      <Select>
                        <SelectTrigger>
                          <SelectValue placeholder="Select theme" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="light">Light</SelectItem>
                          <SelectItem value="dark">Dark</SelectItem>
                          <SelectItem value="system">System</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="grid w-full max-w-sm items-center gap-1.5">
                      <Label>Volume</Label>
                      <Slider defaultValue={[50]} max={100} step={1} />
                    </div>
                  </div>
                </CardContent>
                <CardFooter>
                  <Button 
                    onClick={() => {
                      toast({
                        title: "Form Submitted",
                        description: "Your form has been submitted successfully.",
                      })
                    }}
                  >
                    Submit
                  </Button>
                </CardFooter>
              </Card>
            </div>
          </TabsContent>

          {/* Data Display Tab */}
          <TabsContent value="data">
            <div className="grid gap-6">
              <Card>
                <CardHeader>
                  <CardTitle>Data Display Components</CardTitle>
                  <CardDescription>Various ways to display data.</CardDescription>
                </CardHeader>
                <CardContent className="space-y-6">
                  {/* User Profile */}
                  <div className="flex items-center space-x-4">
                    <HoverCard>
                      <HoverCardTrigger>
                        <Avatar>
                          <AvatarImage src="https://github.com/shadcn.png" />
                          <AvatarFallback>CN</AvatarFallback>
                        </Avatar>
                      </HoverCardTrigger>
                      <HoverCardContent>
                        <div className="space-y-1">
                          <h4 className="text-sm font-semibold">@shadcn</h4>
                          <p className="text-sm">UI Developer and Designer</p>
                        </div>
                      </HoverCardContent>
                    </HoverCard>
                    <div className="space-y-1">
                      <h4 className="text-sm font-semibold">shadcn</h4>
                      <p className="text-sm text-muted-foreground">
                        UI Developer
                        <Badge variant="secondary" className="ml-2">
                          Admin
                        </Badge>
                      </p>
                    </div>
                  </div>

                  {/* Calendar */}
                  <div className="border rounded-lg p-4">
                    <Calendar
                      mode="single"
                      selected={date}
                      onSelect={setDate}
                      className="rounded-md border"
                    />
                  </div>

                  {/* Table */}
                  <Table>
                    <TableCaption>Recent Transactions</TableCaption>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Date</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead className="text-right">Amount</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      <TableRow>
                        <TableCell>2024-01-20</TableCell>
                        <TableCell>
                          <Badge variant="default" className="bg-green-500 hover:bg-green-600">
                            Completed
                          </Badge>
                        </TableCell>
                        <TableCell className="text-right">$250.00</TableCell>
                      </TableRow>
                      <TableRow>
                        <TableCell>2024-01-19</TableCell>
                        <TableCell>
                          <Badge variant="secondary" className="bg-yellow-500 hover:bg-yellow-600">
                            Pending
                          </Badge>
                        </TableCell>
                        <TableCell className="text-right">$120.00</TableCell>
                      </TableRow>
                    </TableBody>
                  </Table>
                </CardContent>
              </Card>
            </div>
          </TabsContent>

          {/* Feedback Tab */}
          <TabsContent value="feedback">
            <Card>
              <CardHeader>
                <CardTitle>Feedback Components</CardTitle>
                <CardDescription>Interactive feedback elements.</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                {/* Progress */}
                <div className="space-y-2">
                  <Label>Upload Progress</Label>
                  <Progress value={progress} />
                </div>

                {/* Toast Examples */}
                <div className="grid gap-2">
                  <Button
                    variant="outline"
                    onClick={() => {
                      toast({
                        variant: "destructive",
                        title: "Error",
                        description: "Something went wrong!",
                      })
                    }}
                  >
                    Show Error Toast
                  </Button>
                  <Button
                    variant="secondary"
                    onClick={() => {
                      toast({
                        title: "Success",
                        description: "Operation completed successfully!",
                      })
                    }}
                  >
                    Show Success Toast
                  </Button>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          {/* Navigation Tab */}
          <TabsContent value="navigation">
            <Card>
              <CardHeader>
                <CardTitle>Navigation Components</CardTitle>
                <CardDescription>Navigation and menu elements.</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                {/* Sheet Example */}
                <Sheet>
                  <SheetTrigger asChild>
                    <Button variant="outline">Open Sheet</Button>
                  </SheetTrigger>
                  <SheetContent>
                    <SheetHeader>
                      <SheetTitle>Sheet Title</SheetTitle>
                      <SheetDescription>
                        This is a sheet component, useful for side panels and drawers.
                      </SheetDescription>
                    </SheetHeader>
                    <div className="py-4">Sheet content goes here.</div>
                  </SheetContent>
                </Sheet>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </main>
    </div>
  )
} 