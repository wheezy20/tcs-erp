export const MONTHS = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

export const periodLabel = (run: { month: number; year: number }) =>
  `${MONTHS[run.month - 1] ?? run.month} ${run.year}`;
