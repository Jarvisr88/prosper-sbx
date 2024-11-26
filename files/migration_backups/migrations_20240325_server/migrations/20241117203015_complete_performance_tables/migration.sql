-- CreateTable
CREATE TABLE "performance_metrics" (
    "metric_id" SERIAL NOT NULL,
    "employee_id" INTEGER NOT NULL,
    "category" TEXT NOT NULL,
    "score" DECIMAL(5,2) NOT NULL,
    "period_start" TIMESTAMP(3) NOT NULL,
    "period_end" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "performance_metrics_pkey" PRIMARY KEY ("metric_id")
);

-- CreateTable
CREATE TABLE "performance_feedback" (
    "feedback_id" SERIAL NOT NULL,
    "employee_id" INTEGER NOT NULL,
    "provider_id" INTEGER NOT NULL,
    "category" TEXT NOT NULL,
    "feedback_type" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "feedback_date" TIMESTAMP(3) NOT NULL,
    "impact_rating" DECIMAL(5,2),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "performance_feedback_pkey" PRIMARY KEY ("feedback_id")
);

-- AddForeignKey
ALTER TABLE "performance_metrics" ADD CONSTRAINT "performance_metrics_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "employee_manager_hierarchy"("employee_id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "performance_feedback" ADD CONSTRAINT "performance_feedback_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "employee_manager_hierarchy"("employee_id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "performance_feedback" ADD CONSTRAINT "performance_feedback_provider_id_fkey" FOREIGN KEY ("provider_id") REFERENCES "employee_manager_hierarchy"("employee_id") ON DELETE RESTRICT ON UPDATE CASCADE;
